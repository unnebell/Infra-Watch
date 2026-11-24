param(
    [int]$Port = 3000,
    [string]$ApiKey = "server-monitor-local-key",
    [string]$BackupToken = "",
    [int]$OfflineThresholdSeconds = 20
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PublicDir = Join-Path $ProjectRoot "public"
$DataDir = Join-Path $ProjectRoot "data"
$BackupDataFile = Join-Path $DataDir "backup-history.json"

if (-not (Test-Path $PublicDir)) {
    Write-Error "Pasta 'public' não encontrada em: $PublicDir"
    exit 1
}

if (-not $BackupToken) {
    $agentCfgPath = Join-Path $ProjectRoot "agent\config.json"
    if (Test-Path $agentCfgPath) {
        try {
            $agentCfg = Get-Content -Path $agentCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($agentCfg.backup -and $agentCfg.backup.apiToken) {
                $BackupToken = [string]$agentCfg.backup.apiToken
            } elseif ($agentCfg.apiKey) {
                $BackupToken = [string]$agentCfg.apiKey
            }
        } catch { }
    }
    if (-not $BackupToken) {
        $BackupToken = $ApiKey
    }
}

$serverCode = @"
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

public class InfraWatchLocalServer
{
    private readonly int _port;
    private readonly string _publicDir;
    private readonly string _apiKey;
    private readonly string _backupToken;
    private readonly string _backupDataFile;
    private readonly int _offlineThresholdSeconds;
    private readonly object _sync = new object();
    private readonly object _backupSync = new object();
    private readonly JavaScriptSerializer _json = new JavaScriptSerializer();

    private TcpListener _listener;
    private volatile bool _running;

    private DateTime? _lastSeenUtc = null;
    private string _currentRawJson = null;
    private readonly List<Dictionary<string, object>> _history = new List<Dictionary<string, object>>();
    private const int MaxHistory = 60;

    private readonly List<Dictionary<string, object>> _backupHistory = new List<Dictionary<string, object>>();
    private const int MaxBackupHistory = 200;

    public InfraWatchLocalServer(int port, string publicDir, string apiKey, int offlineThresholdSeconds, string backupToken, string backupDataFile)
    {
        _port = port;
        _publicDir = Path.GetFullPath(publicDir);
        _apiKey = apiKey ?? "";
        _backupToken = string.IsNullOrEmpty(backupToken) ? _apiKey : backupToken;
        _backupDataFile = backupDataFile ?? "";
        _offlineThresholdSeconds = offlineThresholdSeconds > 0 ? offlineThresholdSeconds : 20;
        _json.MaxJsonLength = 10 * 1024 * 1024;
        LoadBackupHistory();
    }

    public void Start()
    {
        try
        {
            _listener = TcpListener.Create(_port);
            _listener.Start();
        }
        catch
        {
            _listener = new TcpListener(IPAddress.Any, _port);
            _listener.Start();
        }
        _running = true;

        var acceptThread = new Thread(AcceptLoop);
        acceptThread.IsBackground = true;
        acceptThread.Start();
    }

    public void Stop()
    {
        _running = false;
        try { if (_listener != null) _listener.Stop(); } catch { }
    }

    private void AcceptLoop()
    {
        while (_running)
        {
            try
            {
                var client = _listener.AcceptTcpClient();
                ThreadPool.QueueUserWorkItem(_ => HandleClient(client));
            }
            catch (SocketException)
            {
                if (!_running) break;
            }
            catch (ObjectDisposedException)
            {
                break;
            }
            catch
            {
                // Ignora erros transitórios de conexão
            }
        }
    }

    private void HandleClient(TcpClient client)
    {
        using (client)
        {
            client.ReceiveTimeout = 10000;
            client.SendTimeout = 10000;

            try
            {
                using (var stream = client.GetStream())
                {
                    var request = ReadHttpRequest(stream);
                    if (request == null) return;

                    var path = request.Path;
                    var qIndex = path.IndexOf('?');
                    if (qIndex >= 0) path = path.Substring(0, qIndex);

                    if (request.Method == "OPTIONS")
                    {
                        SendResponse(stream, 204, "No Content", "text/plain", new byte[0], true);
                        return;
                    }

                    if (path == "/api/health")
                    {
                        var health = "{\"ok\":true,\"mode\":\"local-powershell\",\"serverTime\":\"" + DateTime.UtcNow.ToString("o") + "\"}";
                        SendJson(stream, 200, "OK", health);
                        return;
                    }

                    if (path == "/api/metrics")
                    {
                        HandleMetricsApi(stream, request);
                        return;
                    }

                    if (path == "/api/backup")
                    {
                        HandleBackupApi(stream, request);
                        return;
                    }

                    if (request.Method == "GET" || request.Method == "HEAD")
                    {
                        ServeStaticFile(stream, path, request.Method == "HEAD");
                        return;
                    }

                    SendJson(stream, 405, "Method Not Allowed", "{\"ok\":false,\"error\":\"Método não permitido.\"}");
                }
            }
            catch
            {
                // Conexão encerrada pelo cliente
            }
        }
    }

    private void HandleMetricsApi(NetworkStream stream, HttpReq req)
    {
        if (req.Method == "POST")
        {
            string providedKey;
            req.Headers.TryGetValue("x-api-key", out providedKey);
            if (!string.IsNullOrEmpty(_apiKey) && providedKey != _apiKey)
            {
                SendJson(stream, 401, "Unauthorized", "{\"ok\":false,\"error\":\"Chave de API inválida (x-api-key).\"}");
                return;
            }

            var bodyText = DecodeRequestBody(req.Body).Trim().TrimStart('\uFEFF');
            if (string.IsNullOrEmpty(bodyText))
            {
                SendJson(stream, 400, "Bad Request", "{\"ok\":false,\"error\":\"Corpo JSON vazio.\"}");
                return;
            }

            try
            {
                var parsed = _json.Deserialize<Dictionary<string, object>>(bodyText);
                if (parsed == null)
                {
                    SendJson(stream, 400, "Bad Request", "{\"ok\":false,\"error\":\"Payload JSON inválido.\"}");
                    return;
                }

                var nowUtc = DateTime.UtcNow;
                var cpuVal = ExtractNestedDouble(parsed, "cpu", "usagePercent");
                var ramVal = ExtractNestedDouble(parsed, "memory", "usagePercent");
                var rxVal = ExtractNestedDouble(parsed, "network", "downloadBps");
                var txVal = ExtractNestedDouble(parsed, "network", "uploadBps");

                var point = new Dictionary<string, object>
                {
                    { "t", nowUtc.ToString("o") },
                    { "cpu", Math.Round(cpuVal, 2) },
                    { "ram", Math.Round(ramVal, 2) },
                    { "rxBps", Math.Round(rxVal, 2) },
                    { "txBps", Math.Round(txVal, 2) }
                };

                lock (_sync)
                {
                    _lastSeenUtc = nowUtc;
                    _currentRawJson = bodyText;
                    _history.Add(point);
                    if (_history.Count > MaxHistory)
                    {
                        _history.RemoveRange(0, _history.Count - MaxHistory);
                    }
                }

                string host = parsed.ContainsKey("hostname") && parsed["hostname"] != null ? parsed["hostname"].ToString() : "desconhecido";
                string ip = parsed.ContainsKey("ip") && parsed["ip"] != null ? parsed["ip"].ToString() : "?";
                Console.WriteLine(string.Format("[{0}] Heartbeat recebido de {1} ({2}) | CPU: {3:0.0}% | RAM: {4:0.0}%",
                    DateTime.Now.ToString("HH:mm:ss"), host, ip, cpuVal, ramVal));

                var resp = "{\"ok\":true,\"receivedAt\":\"" + nowUtc.ToString("o") + "\",\"storage\":\"local-memory\"}";
                SendJson(stream, 200, "OK", resp);
                return;
            }
            catch (Exception ex)
            {
                var errJson = _json.Serialize(new { ok = false, error = "JSON inválido.", details = ex.Message });
                SendJson(stream, 400, "Bad Request", errJson);
                return;
            }
        }

        if (req.Method == "DELETE")
        {
            string providedKey;
            req.Headers.TryGetValue("x-api-key", out providedKey);
            if (!string.IsNullOrEmpty(_apiKey) && providedKey != _apiKey)
            {
                SendJson(stream, 401, "Unauthorized", "{\"ok\":false,\"error\":\"Não autorizado.\"}");
                return;
            }

            lock (_sync)
            {
                _lastSeenUtc = null;
                _currentRawJson = null;
                _history.Clear();
            }

            SendJson(stream, 200, "OK", "{\"ok\":true}");
            return;
        }

        if (req.Method == "GET")
        {
            DateTime? lastSeen;
            string currentJson;
            string historyJson;

            lock (_sync)
            {
                lastSeen = _lastSeenUtc;
                currentJson = _currentRawJson;
                historyJson = _json.Serialize(_history);
            }

            var nowUtc = DateTime.UtcNow;
            string status = "waiting";
            string secondsStr = "null";
            string lastSeenStr = "null";

            if (lastSeen.HasValue && !string.IsNullOrEmpty(currentJson))
            {
                var diffSec = Math.Max(0, (int)Math.Floor((nowUtc - lastSeen.Value).TotalSeconds));
                secondsStr = diffSec.ToString(CultureInfo.InvariantCulture);
                lastSeenStr = "\"" + lastSeen.Value.ToString("o") + "\"";
                status = diffSec <= _offlineThresholdSeconds ? "online" : "offline";
            }

            var sb = new StringBuilder();
            sb.Append("{");
            sb.Append("\"status\":\"").Append(status).Append("\",");
            sb.Append("\"serverTime\":\"").Append(nowUtc.ToString("o")).Append("\",");
            sb.Append("\"lastSeenAt\":").Append(lastSeenStr).Append(",");
            sb.Append("\"secondsSinceLastSeen\":").Append(secondsStr).Append(",");
            sb.Append("\"offlineThresholdSeconds\":").Append(_offlineThresholdSeconds).Append(",");
            sb.Append("\"storage\":\"local-memory\",");
            sb.Append("\"current\":").Append(string.IsNullOrEmpty(currentJson) ? "null" : currentJson).Append(",");
            sb.Append("\"history\":").Append(historyJson);
            sb.Append("}");

            SendJson(stream, 200, "OK", sb.ToString());
            return;
        }

        SendJson(stream, 405, "Method Not Allowed", "{\"ok\":false,\"error\":\"Método não permitido.\"}");
    }

    private double ExtractNestedDouble(Dictionary<string, object> root, string section, string field)
    {
        if (!root.ContainsKey(section) || root[section] == null) return 0;
        var dict = root[section] as Dictionary<string, object>;
        if (dict == null || !dict.ContainsKey(field) || dict[field] == null) return 0;
        try { return Convert.ToDouble(dict[field], CultureInfo.InvariantCulture); } catch { return 0; }
    }

    private void LoadBackupHistory()
    {
        if (string.IsNullOrEmpty(_backupDataFile) || !File.Exists(_backupDataFile)) return;
        try
        {
            var raw = File.ReadAllText(_backupDataFile, Encoding.UTF8);
            if (string.IsNullOrWhiteSpace(raw)) return;
            var list = _json.Deserialize<List<Dictionary<string, object>>>(raw);
            if (list == null) return;
            lock (_backupSync)
            {
                _backupHistory.Clear();
                foreach (var item in list)
                {
                    if (item != null) _backupHistory.Add(item);
                }
                if (_backupHistory.Count > MaxBackupHistory)
                {
                    _backupHistory.RemoveRange(MaxBackupHistory, _backupHistory.Count - MaxBackupHistory);
                }
            }
        }
        catch
        {
            // Ignora arquivo corrompido na inicialização
        }
    }

    private void SaveBackupHistoryUnsafe()
    {
        if (string.IsNullOrEmpty(_backupDataFile)) return;
        try
        {
            var dir = Path.GetDirectoryName(_backupDataFile);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }
            var jsonText = _json.Serialize(_backupHistory);
            var tempFile = _backupDataFile + ".tmp";
            File.WriteAllText(tempFile, jsonText, new UTF8Encoding(false));
            if (File.Exists(_backupDataFile))
            {
                File.Delete(_backupDataFile);
            }
            File.Move(tempFile, _backupDataFile);
        }
        catch
        {
            // Mantém em memória mesmo se falhar gravação em disco
        }
    }

    private bool ValidateBearerToken(HttpReq req)
    {
        if (string.IsNullOrEmpty(_backupToken)) return true;
        string authHeader;
        if (!req.Headers.TryGetValue("authorization", out authHeader) || string.IsNullOrEmpty(authHeader))
        {
            return false;
        }
        authHeader = authHeader.Trim();
        if (!authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }
        var token = authHeader.Substring(7).Trim();
        return FixedTimeEquals(token, _backupToken);
    }

    private static bool FixedTimeEquals(string a, string b)
    {
        if (a == null || b == null || a.Length != b.Length) return false;
        int diff = 0;
        for (int i = 0; i < a.Length; i++)
        {
            diff |= a[i] ^ b[i];
        }
        return diff == 0;
    }

    private static object GetCaseInsensitive(Dictionary<string, object> dict, string key)
    {
        if (dict == null) return null;
        foreach (var kv in dict)
        {
            if (string.Equals(kv.Key, key, StringComparison.OrdinalIgnoreCase))
            {
                return kv.Value;
            }
        }
        return null;
    }

    private static string DecodeRequestBody(byte[] data)
    {
        if (data == null || data.Length == 0) return "";
        try
        {
            var strictUtf8 = new UTF8Encoding(false, true);
            return strictUtf8.GetString(data);
        }
        catch
        {
            try
            {
                return Encoding.GetEncoding(1252).GetString(data);
            }
            catch
            {
                return Encoding.UTF8.GetString(data);
            }
        }
    }

    private static string GetStringField(Dictionary<string, object> dict, string key)
    {
        var val = GetCaseInsensitive(dict, key);
        return val == null ? "" : val.ToString().Trim();
    }

    private void HandleBackupApi(NetworkStream stream, HttpReq req)
    {
        if (req.Method == "POST")
        {
            if (!ValidateBearerToken(req))
            {
                SendJson(stream, 401, "Unauthorized", "{\"ok\":false,\"error\":\"Autenticação Bearer inválida ou ausente (Authorization: Bearer <token>).\"}");
                return;
            }

            var bodyText = DecodeRequestBody(req.Body).Trim().TrimStart('\uFEFF');
            if (string.IsNullOrEmpty(bodyText))
            {
                SendJson(stream, 400, "Bad Request", "{\"ok\":false,\"error\":\"Corpo JSON vazio.\"}");
                return;
            }

            try
            {
                var parsed = _json.Deserialize<Dictionary<string, object>>(bodyText);
                if (parsed == null)
                {
                    SendJson(stream, 400, "Bad Request", "{\"ok\":false,\"error\":\"Payload JSON inválido.\"}");
                    return;
                }

                var tarefa = GetStringField(parsed, "tarefa");
                var agendamento = GetStringField(parsed, "agendamento");
                var statusRaw = GetStringField(parsed, "status").ToLowerInvariant();
                var maquina = GetStringField(parsed, "maquina");
                var codigoObj = GetCaseInsensitive(parsed, "codigo");

                if (string.IsNullOrEmpty(tarefa))
                {
                    SendJson(stream, 400, "Bad Request", "{\"ok\":false,\"error\":\"Campo 'tarefa' é obrigatório.\"}");
                    return;
                }

                if (statusRaw != "sucesso" && statusRaw != "aviso" && statusRaw != "erro" && statusRaw != "cancelado")
                {
                    SendJson(stream, 400, "Bad Request", "{\"ok\":false,\"error\":\"Campo 'status' inválido. Valores aceitos: sucesso, aviso, erro, cancelado.\"}");
                    return;
                }

                object codigoNorm = null;
                if (codigoObj != null)
                {
                    int intVal;
                    if (int.TryParse(codigoObj.ToString().Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out intVal))
                    {
                        codigoNorm = intVal;
                    }
                    else
                    {
                        codigoNorm = codigoObj.ToString().Trim();
                    }
                }

                var nowUtc = DateTime.UtcNow;
                var nowLocal = DateTime.Now;
                var record = new Dictionary<string, object>
                {
                    { "id", nowUtc.Ticks.ToString(CultureInfo.InvariantCulture) },
                    { "recordedAt", nowUtc.ToString("o") },
                    { "serverTimeLocal", nowLocal.ToString("yyyy-MM-dd HH:mm:ss") },
                    { "tarefa", tarefa },
                    { "agendamento", agendamento },
                    { "status", statusRaw },
                    { "codigo", codigoNorm },
                    { "maquina", maquina }
                };

                int totalRecords;
                lock (_backupSync)
                {
                    _backupHistory.Insert(0, record);
                    if (_backupHistory.Count > MaxBackupHistory)
                    {
                        _backupHistory.RemoveRange(MaxBackupHistory, _backupHistory.Count - MaxBackupHistory);
                    }
                    totalRecords = _backupHistory.Count;
                    SaveBackupHistoryUnsafe();
                }

                Console.WriteLine(string.Format("[{0}] Backup registrado | Tarefa: {1} | Status: {2} | Codigo: {3} | Maquina: {4}",
                    nowLocal.ToString("HH:mm:ss"),
                    tarefa,
                    statusRaw,
                    codigoNorm == null ? "-" : codigoNorm.ToString(),
                    string.IsNullOrEmpty(maquina) ? "-" : maquina));

                var respObj = new Dictionary<string, object>
                {
                    { "ok", true },
                    { "record", record },
                    { "totalRecords", totalRecords }
                };
                SendJson(stream, 201, "Created", _json.Serialize(respObj));
                return;
            }
            catch (Exception ex)
            {
                var errJson = _json.Serialize(new { ok = false, error = "JSON inválido.", details = ex.Message });
                SendJson(stream, 400, "Bad Request", errJson);
                return;
            }
        }

        if (req.Method == "DELETE")
        {
            if (!ValidateBearerToken(req))
            {
                SendJson(stream, 401, "Unauthorized", "{\"ok\":false,\"error\":\"Autenticação Bearer inválida ou ausente.\"}");
                return;
            }

            lock (_backupSync)
            {
                _backupHistory.Clear();
                SaveBackupHistoryUnsafe();
            }

            SendJson(stream, 200, "OK", "{\"ok\":true}");
            return;
        }

        if (req.Method == "GET")
        {
            List<Dictionary<string, object>> snapshot;
            lock (_backupSync)
            {
                snapshot = new List<Dictionary<string, object>>(_backupHistory);
            }

            var nowUtc = DateTime.UtcNow;
            Dictionary<string, object> lastBackup = snapshot.Count > 0 ? snapshot[0] : null;
            object secondsSinceObj = null;
            bool overdue24h = false;
            bool overdue48h = false;

            if (lastBackup != null && lastBackup.ContainsKey("recordedAt") && lastBackup["recordedAt"] != null)
            {
                DateTime parsedDt;
                if (DateTime.TryParse(lastBackup["recordedAt"].ToString(), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out parsedDt))
                {
                    var diffSec = Math.Max(0, (long)Math.Floor((nowUtc - parsedDt.ToUniversalTime()).TotalSeconds));
                    secondsSinceObj = diffSec;
                    overdue24h = diffSec >= 86400;
                    overdue48h = diffSec >= 172800;
                }
            }

            var resp = new Dictionary<string, object>
            {
                { "ok", true },
                { "serverTime", nowUtc.ToString("o") },
                { "warnAfterHours", 24 },
                { "criticalAfterHours", 48 },
                { "hasRecords", snapshot.Count > 0 },
                { "overdue24h", overdue24h },
                { "overdue48h", overdue48h },
                { "secondsSinceLastBackup", secondsSinceObj },
                { "totalRecords", snapshot.Count },
                { "lastBackup", lastBackup },
                { "history", snapshot }
            };

            SendJson(stream, 200, "OK", _json.Serialize(resp));
            return;
        }

        SendJson(stream, 405, "Method Not Allowed", "{\"ok\":false,\"error\":\"Método não permitido.\"}");
    }

    private void ServeStaticFile(NetworkStream stream, string urlPath, bool headOnly)
    {
        var relative = urlPath == "/" ? "index.html" : urlPath.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
        var fullPath = Path.GetFullPath(Path.Combine(_publicDir, relative));

        if (!fullPath.StartsWith(_publicDir, StringComparison.OrdinalIgnoreCase) || !File.Exists(fullPath))
        {
            SendJson(stream, 404, "Not Found", "{\"ok\":false,\"error\":\"Arquivo não encontrado.\"}");
            return;
        }

        var bytes = File.ReadAllBytes(fullPath);
        var contentType = GetMimeType(Path.GetExtension(fullPath));
        SendResponse(stream, 200, "OK", contentType, headOnly ? new byte[0] : bytes, false, bytes.Length);
    }

    private static string GetMimeType(string ext)
    {
        switch ((ext ?? "").ToLowerInvariant())
        {
            case ".html": return "text/html; charset=utf-8";
            case ".css": return "text/css; charset=utf-8";
            case ".js": return "application/javascript; charset=utf-8";
            case ".json": return "application/json; charset=utf-8";
            case ".svg": return "image/svg+xml";
            case ".png": return "image/png";
            case ".ico": return "image/x-icon";
            default: return "application/octet-stream";
        }
    }

    private static void SendJson(NetworkStream stream, int code, string reason, string json)
    {
        var bytes = Encoding.UTF8.GetBytes(json);
        SendResponse(stream, code, reason, "application/json; charset=utf-8", bytes, true);
    }

    private static void SendResponse(NetworkStream stream, int code, string reason, string contentType, byte[] body, bool isApi, int? contentLengthOverride = null)
    {
        var len = contentLengthOverride.HasValue ? contentLengthOverride.Value : body.Length;
        var sb = new StringBuilder();
        sb.AppendFormat("HTTP/1.1 {0} {1}\r\n", code, reason);
        sb.AppendFormat("Content-Type: {0}\r\n", contentType);
        sb.AppendFormat("Content-Length: {0}\r\n", len);
        sb.Append("Connection: close\r\n");
        sb.Append("Cache-Control: no-store, max-age=0\r\n");
        if (isApi)
        {
            sb.Append("Access-Control-Allow-Origin: *\r\n");
            sb.Append("Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n");
            sb.Append("Access-Control-Allow-Headers: Content-Type, x-api-key, Authorization\r\n");
        }
        sb.Append("\r\n");

        var headerBytes = Encoding.ASCII.GetBytes(sb.ToString());
        stream.Write(headerBytes, 0, headerBytes.Length);
        if (body.Length > 0)
        {
            stream.Write(body, 0, body.Length);
        }
        stream.Flush();
    }

    private class HttpReq
    {
        public string Method;
        public string Path;
        public Dictionary<string, string> Headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public byte[] Body = new byte[0];
    }

    private static HttpReq ReadHttpRequest(NetworkStream stream)
    {
        var buffer = new byte[8192];
        using (var ms = new MemoryStream())
        {
            int headerEnd = -1;
            while (headerEnd < 0)
            {
                int read = stream.Read(buffer, 0, buffer.Length);
                if (read <= 0) return null;
                ms.Write(buffer, 0, read);

                var arr = ms.ToArray();
                headerEnd = FindHeaderEnd(arr);
                if (ms.Length > 65536 && headerEnd < 0) return null;
            }

            var allBytes = ms.ToArray();
            var headerText = Encoding.ASCII.GetString(allBytes, 0, headerEnd);
            var lines = headerText.Split(new[] { "\r\n" }, StringSplitOptions.None);
            if (lines.Length == 0) return null;

            var firstParts = lines[0].Split(' ');
            if (firstParts.Length < 2) return null;

            var req = new HttpReq
            {
                Method = firstParts[0].ToUpperInvariant(),
                Path = firstParts[1]
            };

            for (int i = 1; i < lines.Length; i++)
            {
                var idx = lines[i].IndexOf(':');
                if (idx > 0)
                {
                    var key = lines[i].Substring(0, idx).Trim();
                    var val = lines[i].Substring(idx + 1).Trim();
                    req.Headers[key] = val;
                }
            }

            string expectVal;
            if (req.Headers.TryGetValue("Expect", out expectVal) && expectVal.IndexOf("100-continue", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                var cont = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n");
                stream.Write(cont, 0, cont.Length);
                stream.Flush();
            }

            int contentLength = 0;
            string clVal;
            if (req.Headers.TryGetValue("Content-Length", out clVal))
            {
                int.TryParse(clVal, out contentLength);
            }

            if (contentLength > 0 && contentLength < 5 * 1024 * 1024)
            {
                var bodyStart = headerEnd + 4;
                var alreadyRead = allBytes.Length - bodyStart;
                var body = new byte[contentLength];
                if (alreadyRead > 0)
                {
                    Buffer.BlockCopy(allBytes, bodyStart, body, 0, Math.Min(alreadyRead, contentLength));
                }

                int totalRead = Math.Min(alreadyRead, contentLength);
                while (totalRead < contentLength)
                {
                    int r = stream.Read(body, totalRead, contentLength - totalRead);
                    if (r <= 0) break;
                    totalRead += r;
                }
                req.Body = body;
            }

            return req;
        }
    }

    private static int FindHeaderEnd(byte[] data)
    {
        for (int i = 0; i <= data.Length - 4; i++)
        {
            if (data[i] == 13 && data[i + 1] == 10 && data[i + 2] == 13 && data[i + 3] == 10)
            {
                return i;
            }
        }
        return -1;
    }
}
"@

Add-Type -TypeDefinition $serverCode -ReferencedAssemblies System.Web.Extensions

$localIps = @()
try {
    $localIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        Select-Object -ExpandProperty IPAddress
} catch { }

$server = New-Object InfraWatchLocalServer($Port, $PublicDir, $ApiKey, $OfflineThresholdSeconds, $BackupToken, $BackupDataFile)
$server.Start()

$primaryIp = if ($localIps.Count -gt 0) { $localIps[0] } else { "127.0.0.1" }

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  InfraWatch - Servidor Local da Dashboard" -ForegroundColor White
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Dashboard local : http://localhost:$Port" -ForegroundColor Green
foreach ($ip in $localIps) {
    Write-Host "  Acesso na rede  : http://${ip}:$Port" -ForegroundColor Green
}
Write-Host "  Endpoint agente : http://${primaryIp}:$Port/api/metrics" -ForegroundColor Yellow
Write-Host "  Endpoint backup : http://${primaryIp}:$Port/api/backup (Bearer)" -ForegroundColor Yellow
Write-Host "  Chave API       : $ApiKey" -ForegroundColor DarkGray
Write-Host "  Token Backup    : $BackupToken" -ForegroundColor DarkGray
Write-Host "  Arquivo Backup  : $BackupDataFile" -ForegroundColor DarkGray
Write-Host "  Limite Offline  : $OfflineThresholdSeconds segundos sem sinal" -ForegroundColor DarkGray
Write-Host "--------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "  Pressione Ctrl+C para encerrar o servidor." -ForegroundColor Gray
Write-Host ""

try {
    while ($true) {
        Start-Sleep -Milliseconds 500
    }
} finally {
    Write-Host "`nEncerrando servidor..." -ForegroundColor Yellow
    $server.Stop()
}
