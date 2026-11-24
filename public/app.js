(() => {
  const POLL_INTERVAL_MS = 3000;
  const GAUGE_CIRCUMFERENCE = 2 * Math.PI * 40; // r = 40

  const state = {
    demoMode: false,
    demoOffline: false,
    demoOfflineSince: null,
    demoHistory: [],
    demoCurrent: null,
    showSystemShares: false,
    activeUsersTab: "active",
    lastResponse: null,
    backupApiResponse: null,
    lastReceivedLocalTime: null,
    apiUnreachable: false,
  };

  // Referências DOM
  const el = {
    serverTitle: document.getElementById("serverTitle"),
    statusBadge: document.getElementById("statusBadge"),
    statusBadgeText: document.getElementById("statusBadgeText"),
    demoPill: document.getElementById("demoPill"),
    metaHost: document.getElementById("metaHost"),
    metaIp: document.getElementById("metaIp"),
    metaGateway: document.getElementById("metaGateway"),
    metaUptime: document.getElementById("metaUptime"),
    lastSyncText: document.getElementById("lastSyncText"),

    offlineBanner: document.getElementById("offlineBanner"),
    offlineServerName: document.getElementById("offlineServerName"),
    offlineDesc: document.getElementById("offlineDesc"),
    offlineElapsed: document.getElementById("offlineElapsed"),
    backupOverdueBanner: document.getElementById("backupOverdueBanner"),
    backupOverdueTitle: document.getElementById("backupOverdueTitle"),
    backupOverdueDesc: document.getElementById("backupOverdueDesc"),
    backupOverdueTimerBox: document.getElementById("backupOverdueTimerBox"),
    backupOverdueElapsed: document.getElementById("backupOverdueElapsed"),
    waitingBanner: document.getElementById("waitingBanner"),
    dashboardContent: document.getElementById("dashboardContent"),

    cpuGaugeArc: document.getElementById("cpuGaugeArc"),
    cpuPercent: document.getElementById("cpuPercent"),
    cpuModel: document.getElementById("cpuModel"),
    cpuCores: document.getElementById("cpuCores"),
    cpuClock: document.getElementById("cpuClock"),
    cpuAvgText: document.getElementById("cpuAvgText"),
    cpuSparkline: document.getElementById("cpuSparkline"),

    ramGaugeArc: document.getElementById("ramGaugeArc"),
    ramPercent: document.getElementById("ramPercent"),
    ramSummary: document.getElementById("ramSummary"),
    ramUsed: document.getElementById("ramUsed"),
    ramFree: document.getElementById("ramFree"),
    ramPeakText: document.getElementById("ramPeakText"),
    ramSparkline: document.getElementById("ramSparkline"),

    diskTotalBadge: document.getElementById("diskTotalBadge"),
    disksList: document.getElementById("disksList"),

    netLinkSpeed: document.getElementById("netLinkSpeed"),
    netDownSpeed: document.getElementById("netDownSpeed"),
    netDownMbps: document.getElementById("netDownMbps"),
    netUpSpeed: document.getElementById("netUpSpeed"),
    netUpMbps: document.getElementById("netUpMbps"),
    netSparkline: document.getElementById("netSparkline"),
    netTotalRx: document.getElementById("netTotalRx"),
    netTotalTx: document.getElementById("netTotalTx"),

    sharesCountChip: document.getElementById("sharesCountChip"),
    toggleSystemShares: document.getElementById("toggleSystemShares"),
    sharesTableBody: document.getElementById("sharesTableBody"),

    backupCard: document.getElementById("backupCard"),
    backupKicker: document.getElementById("backupKicker"),
    backupOneDriveBadge: document.getElementById("backupOneDriveBadge"),
    backupRtsBadge: document.getElementById("backupRtsBadge"),
    backupStatusBadge: document.getElementById("backupStatusBadge"),
    backupStatusText: document.getElementById("backupStatusText"),
    backupLastDate: document.getElementById("backupLastDate"),
    backupAgeText: document.getElementById("backupAgeText"),
    backupJobName: document.getElementById("backupJobName"),
    backupResultBadge: document.getElementById("backupResultBadge"),
    backupDetailText: document.getElementById("backupDetailText"),
    backupSourceText: document.getElementById("backupSourceText"),
    backupDestText: document.getElementById("backupDestText"),
    backupNextText: document.getElementById("backupNextText"),
    backupPolicySummary: document.getElementById("backupPolicySummary"),
    backupFreshnessFill: document.getElementById("backupFreshnessFill"),
    backupFreshnessText: document.getElementById("backupFreshnessText"),
    backupHint: document.getElementById("backupHint"),
    backupHistoryWrap: document.getElementById("backupHistoryWrap"),
    backupHistoryCountChip: document.getElementById("backupHistoryCountChip"),
    backupHistoryTableBody: document.getElementById("backupHistoryTableBody"),
    navBackupDot: document.getElementById("navBackupDot"),

    usersTotalCount: document.getElementById("usersTotalCount"),
    usersEnabledCount: document.getElementById("usersEnabledCount"),
    usersActiveCount: document.getElementById("usersActiveCount"),
    usersSmbCount: document.getElementById("usersSmbCount"),
    activeSessionsBody: document.getElementById("activeSessionsBody"),
    smbSessionsBody: document.getElementById("smbSessionsBody"),
    allAccountsBody: document.getElementById("allAccountsBody"),
    tabUsersActive: document.getElementById("tabUsersActive"),
    tabUsersAll: document.getElementById("tabUsersAll"),

    extrasGrid: document.getElementById("extrasGrid"),
    processesList: document.getElementById("processesList"),
    storageBackendBadge: document.getElementById("storageBackendBadge"),
    sysOs: document.getElementById("sysOs"),
    sysVersion: document.getElementById("sysVersion"),
    sysLastBoot: document.getElementById("sysLastBoot"),
    sysUptime: document.getElementById("sysUptime"),
    adaptersList: document.getElementById("adaptersList"),

    btnDemoToggle: document.getElementById("btnDemoToggle"),
    btnSimulateOffline: document.getElementById("btnSimulateOffline"),
    btnWaitingDemo: document.getElementById("btnWaitingDemo"),
    btnSetupGuide: document.getElementById("btnSetupGuide"),
    btnCloseModal: document.getElementById("btnCloseModal"),
    setupModal: document.getElementById("setupModal"),
    btnManualRefresh: document.getElementById("btnManualRefresh"),
    btnStickyRefresh: document.getElementById("btnStickyRefresh"),
    btnThemeToggle: document.getElementById("btnThemeToggle"),
    metaThemeColor: document.getElementById("metaThemeColor"),
    mainTopbar: document.getElementById("mainTopbar"),
    mobileStickyBar: document.getElementById("mobileStickyBar"),
    stickyStatusBadge: document.getElementById("stickyStatusBadge"),
    stickyStatusText: document.getElementById("stickyStatusText"),
    stickyServerTitle: document.getElementById("stickyServerTitle"),
    stickyCpu: document.getElementById("stickyCpu"),
    stickyRam: document.getElementById("stickyRam"),
    mobileBottomNav: document.getElementById("mobileBottomNav"),
    navSharesBadge: document.getElementById("navSharesBadge"),
    navUsersBadge: document.getElementById("navUsersBadge"),
    toast: document.getElementById("toast"),
  };

  // Helpers de formatação
  function toArray(val) {
    if (!val) return [];
    const arr = Array.isArray(val) ? val : [val];
    return arr.flat(Infinity).filter((item) => item && typeof item === "object");
  }

  const CP1252_REVERSE = {
    0x20ac: 0x80, 0x201a: 0x82, 0x0192: 0x83, 0x201e: 0x84, 0x2026: 0x85,
    0x2020: 0x86, 0x2021: 0x87, 0x02c6: 0x88, 0x2030: 0x89, 0x0160: 0x8a,
    0x2039: 0x8b, 0x0152: 0x8c, 0x017d: 0x8e, 0x2018: 0x91, 0x2019: 0x92,
    0x201c: 0x93, 0x201d: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
    0x02dc: 0x98, 0x2122: 0x99, 0x0161: 0x9a, 0x203a: 0x9b, 0x0153: 0x9c,
    0x017e: 0x9e, 0x0178: 0x9f,
  };

  function repairMojibake(str) {
    const s = String(str ?? "");
    if (!/[\u00C2\u00C3\u00E2]/.test(s)) return s;
    try {
      const bytes = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) {
        const code = s.charCodeAt(i);
        if (code <= 0xff) {
          bytes[i] = code;
        } else if (CP1252_REVERSE[code] !== undefined) {
          bytes[i] = CP1252_REVERSE[code];
        } else {
          return s;
        }
      }
      return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch {
      return s;
    }
  }

  function deepRepairMojibake(val) {
    if (typeof val === "string") return repairMojibake(val);
    if (Array.isArray(val)) return val.map(deepRepairMojibake);
    if (val && typeof val === "object") {
      const out = {};
      for (const k of Object.keys(val)) {
        out[k] = deepRepairMojibake(val[k]);
      }
      return out;
    }
    return val;
  }

  function escapeHtml(str) {
    return repairMojibake(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function formatBytes(bytes, decimals = 1) {
    const n = Number(bytes);
    if (!Number.isFinite(n) || n <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB", "TB"];
    const idx = Math.min(units.length - 1, Math.floor(Math.log(n) / Math.log(1024)));
    const val = n / Math.pow(1024, idx);
    return `${val.toFixed(idx === 0 ? 0 : decimals)} ${units[idx]}`;
  }

  function formatRateBps(bytesPerSec) {
    const n = Math.max(0, Number(bytesPerSec) || 0);
    if (n < 1024) return `${n.toFixed(0)} B/s`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB/s`;
    return `${(n / (1024 * 1024)).toFixed(2)} MB/s`;
  }

  function formatMbps(bytesPerSec) {
    const mbps = ((Math.max(0, Number(bytesPerSec) || 0) * 8) / 1_000_000);
    return `${mbps.toFixed(2)} Mbps`;
  }

  function formatDuration(totalSeconds) {
    const sec = Math.max(0, Math.floor(Number(totalSeconds) || 0));
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (d > 0) return `${d}d ${h}h ${m}m`;
    if (h > 0) return `${h}h ${m}m ${s}s`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  }

  function formatDateTime(iso) {
    if (!iso) return "—";
    const dt = new Date(iso);
    if (Number.isNaN(dt.getTime())) return String(iso);
    return dt.toLocaleString("pt-BR", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }

  let toastTimer = null;
  function showToast(msg) {
    el.toast.textContent = msg;
    el.toast.classList.remove("hidden");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.toast.classList.add("hidden"), 2500);
  }

  // Atualização de medidores SVG
  function setRadialGauge(arcEl, pct) {
    const clamped = Math.min(100, Math.max(0, Number(pct) || 0));
    const offset = GAUGE_CIRCUMFERENCE * (1 - clamped / 100);
    arcEl.style.strokeDasharray = `${GAUGE_CIRCUMFERENCE}`;
    arcEl.style.strokeDashoffset = `${offset}`;
    arcEl.classList.remove("gauge-warn", "gauge-crit");
    if (clamped >= 90) arcEl.classList.add("gauge-crit");
    else if (clamped >= 75) arcEl.classList.add("gauge-warn");
  }

  function renderSingleSparkline(svgEl, values, color, maxVal = 100) {
    const w = 260;
    const h = 54;
    const pad = 4;
    const pts = values.slice(-40);
    if (pts.length < 2) {
      svgEl.innerHTML = `<line x1="0" y1="${h - pad}" x2="${w}" y2="${h - pad}" stroke="${color}" stroke-opacity="0.25" stroke-width="1.5" stroke-dasharray="4 4"/>`;
      return;
    }

    const peak = Math.max(maxVal, ...pts, 1);
    const stepX = w / (pts.length - 1);
    const coords = pts.map((v, i) => {
      const x = i * stepX;
      const y = h - pad - ((Math.max(0, v) / peak) * (h - pad * 2));
      return [x, y];
    });

    const linePath = coords.map(([x, y], i) => `${i === 0 ? "M" : "L"}${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
    const areaPath = `${linePath} L${w},${h} L0,${h} Z`;
    const gradId = `grad-${svgEl.id}`;

    svgEl.innerHTML = `
      <defs>
        <linearGradient id="${gradId}" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="${color}" stop-opacity="0.32" />
          <stop offset="100%" stop-color="${color}" stop-opacity="0.02" />
        </linearGradient>
      </defs>
      <path d="${areaPath}" fill="url(#${gradId})"></path>
      <path d="${linePath}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"></path>
    `;
  }

  function renderDualSparkline(svgEl, seriesA, seriesB, colorA, colorB) {
    const w = 260;
    const h = 54;
    const pad = 4;
    const a = seriesA.slice(-40);
    const b = seriesB.slice(-40);
    if (a.length < 2) {
      svgEl.innerHTML = `<line x1="0" y1="${h - pad}" x2="${w}" y2="${h - pad}" stroke="${colorA}" stroke-opacity="0.25" stroke-width="1.5" stroke-dasharray="4 4"/>`;
      return;
    }

    const peak = Math.max(...a, ...b, 1024);
    const stepX = w / (a.length - 1);

    const buildPath = (arr) =>
      arr
        .map((v, i) => {
          const x = i * stepX;
          const y = h - pad - ((Math.max(0, v) / peak) * (h - pad * 2));
          return `${i === 0 ? "M" : "L"}${x.toFixed(1)},${y.toFixed(1)}`;
        })
        .join(" ");

    svgEl.innerHTML = `
      <path d="${buildPath(b)}" fill="none" stroke="${colorB}" stroke-width="1.8" stroke-opacity="0.85" stroke-linejoin="round"></path>
      <path d="${buildPath(a)}" fill="none" stroke="${colorA}" stroke-width="2.1" stroke-linejoin="round"></path>
    `;
  }

  // Renderização completa da UI
  function renderDashboard(apiData) {
    state.lastResponse = apiData;

    const status = apiData?.status || "waiting";
    const data = apiData?.current || null;
    const history = toArray(apiData?.history);

    // Status pill e banners
    el.statusBadge.className = `status-badge status-${status}`;
    if (el.stickyStatusBadge) {
      el.stickyStatusBadge.className = `status-badge status-compact status-${status}`;
    }
    if (status === "online") {
      el.statusBadgeText.textContent = "ONLINE";
      if (el.stickyStatusText) el.stickyStatusText.textContent = "ONLINE";
      el.offlineBanner.classList.add("hidden");
      el.waitingBanner.classList.add("hidden");
      el.dashboardContent.classList.remove("is-offline");
    } else if (status === "offline") {
      el.statusBadgeText.textContent = "OFFLINE";
      if (el.stickyStatusText) el.stickyStatusText.textContent = "OFFLINE";
      el.offlineBanner.classList.remove("hidden");
      el.waitingBanner.classList.add("hidden");
      el.dashboardContent.classList.add("is-offline");
      const sName = data ? `${data.hostname || "Servidor"} (${data.ip || "—"})` : "Servidor";
      el.offlineServerName.textContent = sName;
      el.offlineDesc.textContent = state.apiUnreachable
        ? "Não foi possível comunicar com o servidor da dashboard (/api/metrics). Verifique se o serviço local ou a rede está ativa."
        : `Último sinal recebido em ${formatDateTime(apiData.lastSeenAt)}. Verifique energia, rede${data?.gateway && data.gateway !== "-" ? ` (gateway ${data.gateway})` : ""} e o agente no servidor. Os dados abaixo exibem a última leitura conhecida.`;
    } else {
      el.statusBadgeText.textContent = "AGUARDANDO";
      if (el.stickyStatusText) el.stickyStatusText.textContent = "AGUARDANDO";
      el.offlineBanner.classList.add("hidden");
      el.waitingBanner.classList.remove("hidden");
      el.dashboardContent.classList.remove("is-offline");
    }

    el.storageBackendBadge.textContent =
      apiData?.storage === "redis"
        ? "Vercel + Redis"
        : state.demoMode
          ? "Simulação"
          : "Local (Memória)";

    updateTimeTickers();

    if (!data) return;

    // Cabeçalho
    el.serverTitle.textContent = data.label || `Servidor ${data.hostname || "Local"}`;
    if (el.stickyServerTitle) el.stickyServerTitle.textContent = data.hostname || "Servidor";
    el.metaHost.textContent = data.hostname || "—";
    el.metaIp.textContent = data.ip || "—";
    el.metaGateway.textContent = data.gateway || "—";
    el.metaUptime.textContent = data.os?.uptimeSeconds != null ? formatDuration(data.os.uptimeSeconds) : "—";

    // 1. CPU
    const cpuPct = Number(data.cpu?.usagePercent ?? 0);
    setRadialGauge(el.cpuGaugeArc, cpuPct);
    const cpuFormatted = cpuPct > 0 && cpuPct < 10 ? cpuPct.toFixed(1) : cpuPct.toFixed(0);
    el.cpuPercent.textContent = cpuFormatted;
    if (el.stickyCpu) el.stickyCpu.textContent = `${cpuFormatted}%`;
    el.cpuModel.textContent = data.cpu?.name || "Processador Windows";
    el.cpuModel.title = data.cpu?.name || "";
    const coresNum = Number(data.cpu?.cores || 0);
    const logicalNum = Number(data.cpu?.logicalProcessors || 0);
    el.cpuCores.textContent = coresNum > 0 ? `${coresNum}C / ${logicalNum || coresNum}T` : (logicalNum > 0 ? `${logicalNum} Threads` : "—");
    el.cpuClock.textContent = data.cpu?.clockMhz ? `${(data.cpu.clockMhz / 1000).toFixed(2)} GHz` : "—";

    const cpuSeries = history.map((h) => Number(h.cpu) || 0);
    if (cpuSeries.length > 0) {
      const avg = cpuSeries.reduce((s, v) => s + v, 0) / cpuSeries.length;
      el.cpuAvgText.textContent = `Média: ${avg.toFixed(1)}%`;
    }
    renderSingleSparkline(el.cpuSparkline, cpuSeries, "#38bdf8", 100);

    // 2. Memória RAM
    const ramPct = Number(data.memory?.usagePercent ?? 0);
    setRadialGauge(el.ramGaugeArc, ramPct);
    el.ramPercent.textContent = ramPct.toFixed(0);
    if (el.stickyRam) el.stickyRam.textContent = `${ramPct.toFixed(0)}%`;
    el.ramSummary.textContent = `${formatBytes(data.memory?.usedBytes)} de ${formatBytes(data.memory?.totalBytes)}`;
    el.ramUsed.textContent = formatBytes(data.memory?.usedBytes);
    el.ramFree.textContent = formatBytes(data.memory?.freeBytes);

    const ramSeries = history.map((h) => Number(h.ram) || 0);
    if (ramSeries.length > 0) {
      const peak = Math.max(...ramSeries);
      el.ramPeakText.textContent = `Pico: ${peak.toFixed(1)}%`;
    }
    renderSingleSparkline(el.ramSparkline, ramSeries, "#a78bfa", 100);

    // 3. Armazenamento (Discos)
    const disks = toArray(data.disks);
    if (disks.length === 0) {
      el.diskTotalBadge.textContent = "0 volumes";
      el.disksList.innerHTML = `<div class="empty-state">Nenhum volume reportado.</div>`;
    } else {
      const totalSpace = disks.reduce((s, d) => s + (Number(d.totalBytes) || 0), 0);
      const freeSpace = disks.reduce((s, d) => s + (Number(d.freeBytes) || 0), 0);
      el.diskTotalBadge.textContent = `${formatBytes(freeSpace)} livres / ${formatBytes(totalSpace)}`;

      el.disksList.innerHTML = disks
        .map((d) => {
          const pct = Math.min(100, Math.max(0, Number(d.usagePercent) || 0));
          const cls = pct >= 90 ? "crit" : pct >= 75 ? "warn" : "";
          return `
            <div class="disk-item">
              <div class="disk-top">
                <span class="disk-name">${escapeHtml(d.drive)} <small>${escapeHtml(d.label || "Disco Local")} (${escapeHtml(d.fileSystem || "NTFS")})</small></span>
                <span class="disk-pct">${pct.toFixed(1)}%</span>
              </div>
              <div class="progress-bar">
                <div class="progress-fill ${cls}" style="width: ${pct}%"></div>
              </div>
              <div class="disk-sub">
                <span>Usado: ${formatBytes(d.usedBytes)}</span>
                <span>Livre: ${formatBytes(d.freeBytes)} de ${formatBytes(d.totalBytes)}</span>
              </div>
            </div>
          `;
        })
        .join("");
    }

    // 4. Rede
    const downBps = Number(data.network?.downloadBps || 0);
    const upBps = Number(data.network?.uploadBps || 0);
    const adapters = toArray(data.network?.adapters);
    el.netLinkSpeed.textContent = adapters[0]?.linkSpeed || "Ethernet";
    el.netDownSpeed.textContent = formatRateBps(downBps);
    el.netDownMbps.textContent = formatMbps(downBps);
    el.netUpSpeed.textContent = formatRateBps(upBps);
    el.netUpMbps.textContent = formatMbps(upBps);
    el.netTotalRx.textContent = formatBytes(data.network?.totalRxBytes);
    el.netTotalTx.textContent = formatBytes(data.network?.totalTxBytes);

    renderDualSparkline(
      el.netSparkline,
      history.map((h) => Number(h.rxBps) || 0),
      history.map((h) => Number(h.txBps) || 0),
      "#38bdf8",
      "#a78bfa"
    );

    // 4.5. Último Backup (prioriza registros de POST /api/backup, com fallback do agente)
    refreshBackupView();

    // 5. Pastas Compartilhadas
    renderShares(toArray(data.shares), data.ip || data.hostname || "servidor");

    // 6. Usuários e Sessões
    renderUsers(data.users || {});

    // 7. Módulos Extras & Serviços
    renderExtras(toArray(data.extras));

    // 8. Principais Processos
    renderProcesses(toArray(data.topProcesses), Number(data.memory?.totalBytes) || 1);

    // 9. Detalhes do Sistema e Adaptadores
    el.sysOs.textContent = data.os?.caption || "Windows 10";
    el.sysVersion.textContent = `${data.os?.version || "—"} (${data.os?.architecture || "64-bit"})`;
    el.sysLastBoot.textContent = formatDateTime(data.os?.lastBoot);
    el.sysUptime.textContent = data.os?.uptimeSeconds != null ? formatDuration(data.os.uptimeSeconds) : "—";

    if (adapters.length === 0) {
      el.adaptersList.innerHTML = `<div class="empty-state">Nenhum adaptador de rede ativo.</div>`;
    } else {
      el.adaptersList.innerHTML = adapters
        .map(
          (a) => `
            <div class="adapter-item">
              <div class="adapter-head">
                <span>${escapeHtml(a.name || "Adaptador")}</span>
                <span class="badge-sm badge-ok">${escapeHtml(a.linkSpeed || a.status || "Ativo")}</span>
              </div>
              <div class="adapter-meta">
                <span>IP: ${escapeHtml(a.ip || "—")}</span>
                <span class="adapter-sep">·</span>
                <span>GW: ${escapeHtml(a.gateway || "—")}</span>
                <span class="adapter-sep">·</span>
                <span>MAC: ${escapeHtml(a.mac || "—")}</span>
              </div>
            </div>
          `
        )
        .join("");
    }
  }

  function renderShares(shares, hostOrIp) {
    const userShares = shares.filter((s) => !s.isSystem);
    const visibleShares = state.showSystemShares ? shares : userShares;
    el.sharesCountChip.textContent = `${userShares.length} pública${userShares.length === 1 ? "" : "s"}`;

    if (el.navSharesBadge) {
      const shareCount = visibleShares.length;
      el.navSharesBadge.textContent = String(shareCount);
      el.navSharesBadge.classList.toggle("hidden", shareCount === 0);
    }

    if (visibleShares.length === 0) {
      el.sharesTableBody.innerHTML = `<tr class="empty-row"><td colspan="5" class="empty-cell">Nenhuma pasta compartilhada de usuário encontrada.${shares.length > 0 ? ' Marque "Exibir ocultas/sistema" para ver compartilhamentos administrativos.' : ""}</td></tr>`;
      return;
    }

    el.sharesTableBody.innerHTML = visibleShares
      .map((s) => {
        const uncPath = `\\\\${hostOrIp}\\${s.name}`;
        const usersNum = Number(s.currentUsers || 0);
        const usersBadge = usersNum > 0 ? "badge-ok" : "badge-neutral";
        return `
          <tr>
            <td class="cell-primary" data-label="Pasta / Rede">
              <div class="share-name-cell">
                <span>${escapeHtml(s.name)}</span>
                ${s.isSystem ? '<span class="tag-sys">SISTEMA</span>' : ""}
              </div>
            </td>
            <td class="mono cell-wrap" data-label="Caminho Local">${escapeHtml(s.path || "—")}</td>
            <td class="cell-wrap" data-label="Descrição">${escapeHtml(s.description || "—")}</td>
            <td class="num-col" data-label="Acessos"><span class="badge-sm ${usersBadge}">${usersNum}</span></td>
            <td class="act-col cell-action" data-label="Ação">
              <button type="button" class="btn-copy" data-copy-unc="${escapeHtml(uncPath)}">Copiar UNC <span class="btn-copy-unc-mobile">${escapeHtml(uncPath)}</span></button>
            </td>
          </tr>
        `;
      })
      .join("");
  }

  function renderUsers(users) {
    const accounts = toArray(users.accounts);
    const activeSessions = toArray(users.activeSessions);
    const smbSessions = toArray(users.smbSessions);

    const activeCount = users.activeSessionsCount ?? activeSessions.filter((s) => s.isActive).length;
    const smbCount = users.smbSessionsCount ?? smbSessions.length;

    el.usersTotalCount.textContent = users.totalAccounts ?? accounts.length;
    el.usersEnabledCount.textContent = users.enabledAccounts ?? accounts.filter((a) => a.enabled).length;
    el.usersActiveCount.textContent = activeCount;
    el.usersSmbCount.textContent = smbCount;

    if (el.navUsersBadge) {
      const totalOnline = Number(activeCount || 0) + Number(smbCount || 0);
      el.navUsersBadge.textContent = String(totalOnline);
      el.navUsersBadge.classList.toggle("hidden", totalOnline === 0);
    }

    if (activeSessions.length === 0) {
      el.activeSessionsBody.innerHTML = `<tr class="empty-row"><td colspan="4" class="empty-cell">Nenhuma sessão interativa/RDP detectada.</td></tr>`;
    } else {
      el.activeSessionsBody.innerHTML = activeSessions
        .map((s) => {
          const badge = s.isActive ? "badge-ok" : "badge-warn";
          return `
            <tr>
              <td class="cell-primary" data-label="Usuário"><strong>${escapeHtml(s.username)}</strong></td>
              <td data-label="Origem">${escapeHtml(s.source || s.sessionName || "Console")}</td>
              <td data-label="Estado"><span class="badge-sm ${badge}">${escapeHtml(s.state || "Ativo")}</span></td>
              <td class="mono" data-label="Logon">${escapeHtml(s.logonTime || "—")}</td>
            </tr>
          `;
        })
        .join("");
    }

    if (smbSessions.length === 0) {
      el.smbSessionsBody.innerHTML = `<tr class="empty-row"><td colspan="4" class="empty-cell">Nenhuma estação acessando pastas SMB agora.</td></tr>`;
    } else {
      el.smbSessionsBody.innerHTML = smbSessions
        .map(
          (s) => `
            <tr>
              <td class="cell-primary" data-label="Usuário"><strong>${escapeHtml(s.username)}</strong></td>
              <td class="mono" data-label="IP / Estação">${escapeHtml(s.clientIp || "—")}</td>
              <td class="num-col" data-label="Arq. Abertos">${Number(s.numOpens || 0)}</td>
              <td class="num-col" data-label="Tempo">${formatDuration(s.secondsConnected || 0)}</td>
            </tr>
          `
        )
        .join("");
    }

    if (accounts.length === 0) {
      el.allAccountsBody.innerHTML = `<tr class="empty-row"><td colspan="4" class="empty-cell">Nenhuma conta local reportada.</td></tr>`;
    } else {
      const sorted = [...accounts].sort((a, b) => Number(b.isActive) - Number(a.isActive) || Number(b.enabled) - Number(a.enabled));
      el.allAccountsBody.innerHTML = sorted
        .map((u) => {
          let badgeClass = "badge-neutral";
          let statusLabel = "Offline";
          if (!u.enabled) {
            badgeClass = "badge-err";
            statusLabel = "Desabilitada";
          } else if (u.isActive) {
            badgeClass = "badge-ok";
            statusLabel = "Ativo Agora";
          }
          return `
            <tr>
              <td class="cell-primary" data-label="Usuário"><strong>${escapeHtml(u.name)}</strong></td>
              <td class="cell-wrap" data-label="Nome Completo">${escapeHtml(u.fullName || u.description || "—")}</td>
              <td data-label="Status"><span class="badge-sm ${badgeClass}">${statusLabel}</span></td>
              <td class="mono" data-label="Último Logon">${formatDateTime(u.lastLogon)}</td>
            </tr>
          `;
        })
        .join("");
    }
  }

  function renderExtras(extras) {
    if (extras.length === 0) {
      el.extrasGrid.innerHTML = `<div class="empty-state">Nenhum módulo extra configurado. Edite <code>agent/config.json</code> para adicionar serviços ou verificações.</div>`;
      return;
    }

    el.extrasGrid.innerHTML = extras
      .map((item) => {
        const map = { ok: "badge-ok", warn: "badge-warn", error: "badge-err", neutral: "badge-neutral" };
        const cls = map[item.status] || "badge-neutral";
        return `
          <div class="extra-item">
            <div class="extra-top">
              <span class="extra-title">${escapeHtml(item.title)}</span>
              <span class="badge-sm ${cls}">${escapeHtml(item.value)}</span>
            </div>
            <span class="extra-detail">${escapeHtml(item.detail || "")}</span>
          </div>
        `;
      })
      .join("");
  }

  function renderProcesses(procs, totalMemBytes) {
    if (procs.length === 0) {
      el.processesList.innerHTML = `<div class="empty-state">Nenhum processo coletado ainda.</div>`;
      return;
    }

    const maxMem = Math.max(...procs.map((p) => Number(p.memoryBytes) || 0), 1);
    el.processesList.innerHTML = procs
      .map((p) => {
        const mem = Number(p.memoryBytes) || 0;
        const barPct = Math.min(100, (mem / maxMem) * 100);
        const totalPct = totalMemBytes > 0 ? ((mem / totalMemBytes) * 100).toFixed(1) : "0.0";
        return `
          <div class="proc-item">
            <div class="proc-row">
              <span class="proc-name">${escapeHtml(p.name)} <small>PID ${escapeHtml(p.pid)}</small></span>
              <span class="proc-mem">${formatBytes(mem)} <small>(${totalPct}%)</small></span>
            </div>
            <div class="progress-bar">
              <div class="progress-fill" style="width:${barPct.toFixed(1)}%; background: var(--cyan);"></div>
            </div>
          </div>
        `;
      })
      .join("");
  }

  function mapBackupApiStatus(rawStatus) {
    const s = String(rawStatus || "").toLowerCase().trim();
    if (s === "sucesso") return { key: "sucesso", label: "Sucesso", badge: "badge-ok", level: "ok" };
    if (s === "aviso") return { key: "aviso", label: "Aviso", badge: "badge-warn", level: "warn" };
    if (s === "erro") return { key: "erro", label: "Erro", badge: "badge-err", level: "error" };
    if (s === "cancelado") return { key: "cancelado", label: "Cancelado", badge: "badge-err", level: "error" };
    return { key: s || "desconhecido", label: rawStatus || "—", badge: "badge-neutral", level: "unknown" };
  }

  function getActiveBackupModel() {
    const agentBackup = state.lastResponse?.current?.backup || null;

    if (state.demoMode && state.demoCurrent?.backupApi) {
      return { api: state.demoCurrent.backupApi, agent: agentBackup };
    }

    return { api: state.backupApiResponse, agent: agentBackup };
  }

  function refreshBackupView() {
    if (!el.backupCard) return;
    const { api, agent } = getActiveBackupModel();

    // Badges de processos ativos (OneDrive / RealTimeSync) quando reportados pelo agente
    if (agent && typeof agent.oneDriveRunning === "boolean") {
      el.backupOneDriveBadge.classList.remove("hidden");
      el.backupOneDriveBadge.className = `badge-sm ${agent.oneDriveRunning ? "badge-ok" : "badge-warn"}`;
      el.backupOneDriveBadge.textContent = agent.oneDriveRunning ? "OneDrive: Ativo" : "OneDrive: Inativo";
      el.backupRtsBadge.classList.toggle("hidden", !agent.realTimeSyncRunning);
    } else {
      el.backupOneDriveBadge.classList.add("hidden");
      el.backupRtsBadge.classList.add("hidden");
    }

    const apiHistory = toArray(api?.history);
    const hasApiRecords = apiHistory.length > 0;

    if (hasApiRecords) {
      const latest = apiHistory[0];
      const warnH = Number(api?.warnAfterHours) || 24;
      const critH = Number(api?.criticalAfterHours) || 48;
      const stInfo = mapBackupApiStatus(latest.status);

      el.backupKicker.textContent = "Proteção de Dados · Endpoint POST /api/backup";
      if (el.backupHistoryCountChip) {
        el.backupHistoryCountChip.textContent = `${apiHistory.length} registro${apiHistory.length === 1 ? "" : "s"}`;
      }

      el.backupLastDate.textContent = formatDateTime(latest.recordedAt);
      el.backupJobName.textContent = latest.tarefa || "Backup";
      el.backupResultBadge.className = `badge-sm ${stInfo.badge}`;
      el.backupResultBadge.textContent = stInfo.label;

      const codigoStr = latest.codigo !== null && latest.codigo !== undefined && latest.codigo !== "" ? String(latest.codigo) : "—";
      el.backupDetailText.textContent = `Código de retorno: ${codigoStr}`;

      el.backupSourceText.textContent = latest.agendamento || "Execução manual / sem agendamento";
      el.backupDestText.textContent = `Máquina: ${latest.maquina || "—"}`;
      el.backupNextText.classList.add("hidden");

      el.backupPolicySummary.textContent = `Alerta > ${warnH}h · Crítico > ${critH}h`;
      el.backupHint.classList.add("hidden");

      renderBackupHistoryTable(apiHistory);
      updateBackupLiveStatus({
        lastBackupAt: latest.recordedAt,
        level: stInfo.level,
        statusLabel: stInfo.label,
        tarefa: latest.tarefa || "Backup",
        maquina: latest.maquina || "Servidor",
        warnAfterHours: warnH,
        criticalAfterHours: critH,
        syncRunning: Boolean(agent?.syncRunning),
      });
      return;
    }

    // Fallback: dados coletados automaticamente pelo agente (FreeFileSync) caso ainda não haja POST /api/backup
    if (agent && agent.lastBackupAt) {
      const warnH = Number(agent.warnAfterHours) || 24;
      const critH = Number(agent.criticalAfterHours) || 48;
      const runs = toArray(agent.recentRuns);

      el.backupKicker.textContent = `Proteção de Dados · ${agent.label || "FreeFileSync → OneDrive"}`;
      if (el.backupHistoryCountChip) {
        el.backupHistoryCountChip.textContent = `${runs.length} registro${runs.length === 1 ? "" : "s"}`;
      }

      el.backupLastDate.textContent = formatDateTime(agent.lastBackupAt);
      el.backupJobName.textContent = agent.jobName || agent.label || "FreeFileSync";
      const badgeMap = { ok: "badge-ok", warn: "badge-warn", error: "badge-err", running: "badge-info" };
      el.backupResultBadge.className = `badge-sm ${badgeMap[agent.status] || "badge-neutral"}`;
      el.backupResultBadge.textContent = agent.syncRunning ? "Sincronizando..." : (agent.result || "Concluído");
      el.backupDetailText.textContent = agent.detail || "Detectado automaticamente no servidor.";
      el.backupSourceText.textContent = agent.source || "FreeFileSync → OneDrive";
      el.backupDestText.textContent = agent.destinationPath || agent.logFile || "—";

      if (agent.nextScheduledAt) {
        el.backupNextText.textContent = `Próximo agendado: ${formatDateTime(agent.nextScheduledAt)}`;
        el.backupNextText.classList.remove("hidden");
      } else {
        el.backupNextText.classList.add("hidden");
      }

      el.backupPolicySummary.textContent = `Alerta > ${warnH}h · Crítico > ${critH}h`;
      el.backupHint.classList.add("hidden");

      const mappedRuns = runs.map((r) => ({
        recordedAt: r.time,
        tarefa: r.name || "FreeFileSync",
        agendamento: r.summary || "Automático",
        maquina: state.lastResponse?.current?.hostname || "Servidor",
        codigo: r.status === "ok" ? 0 : r.status === "warn" ? 1 : 2,
        status: r.status === "ok" ? "sucesso" : r.status === "warn" ? "aviso" : "erro",
      }));
      renderBackupHistoryTable(mappedRuns);
      updateBackupLiveStatus({
        lastBackupAt: agent.lastBackupAt,
        level: agent.status === "error" ? "error" : agent.status === "warn" ? "warn" : "ok",
        statusLabel: agent.statusLabel || "Em dia",
        tarefa: agent.jobName || "Backup",
        maquina: state.lastResponse?.current?.hostname || "Servidor",
        warnAfterHours: warnH,
        criticalAfterHours: critH,
        syncRunning: Boolean(agent.syncRunning),
      });
      return;
    }

    // Estado inicial sem nenhum registro
    el.backupKicker.textContent = "Proteção de Dados · Endpoint POST /api/backup";
    if (el.backupHistoryCountChip) el.backupHistoryCountChip.textContent = "0 registros";
    el.backupStatusBadge.className = "status-badge status-waiting";
    el.backupStatusText.textContent = "SEM REGISTRO";
    el.backupCard.className = "card backup-card";
    el.backupLastDate.textContent = "Nenhum registro";
    el.backupAgeText.textContent = "Aguardando primeira chamada em POST /api/backup";
    el.backupJobName.textContent = "—";
    el.backupResultBadge.className = "badge-sm badge-neutral";
    el.backupResultBadge.textContent = "—";
    el.backupDetailText.textContent = "Código de retorno: —";
    el.backupSourceText.textContent = "—";
    el.backupDestText.textContent = "Máquina: —";
    el.backupNextText.classList.add("hidden");
    el.backupPolicySummary.textContent = "Alerta > 24h · Crítico > 48h";
    el.backupFreshnessFill.style.width = "0%";
    el.backupFreshnessFill.className = "progress-fill";
    el.backupFreshnessText.textContent = "Aguardando primeiro registro de backup";
    el.backupHint.classList.remove("hidden");
    if (el.navBackupDot) el.navBackupDot.className = "mobile-nav-dot dot-warn";
    if (el.backupOverdueBanner) el.backupOverdueBanner.classList.add("hidden");
    renderBackupHistoryTable([]);
  }

  function renderBackupHistoryTable(records) {
    if (!el.backupHistoryTableBody) return;
    if (!records || records.length === 0) {
      el.backupHistoryTableBody.innerHTML = `<tr class="empty-row"><td colspan="6" class="empty-cell">Nenhum registro de backup recebido ainda.</td></tr>`;
      return;
    }

    el.backupHistoryTableBody.innerHTML = records
      .slice(0, 30)
      .map((rec) => {
        const stInfo = mapBackupApiStatus(rec.status);
        const codigoStr = rec.codigo !== null && rec.codigo !== undefined && rec.codigo !== "" ? String(rec.codigo) : "—";
        return `
          <tr>
            <td class="cell-primary mono" data-label="Data / Hora">${formatDateTime(rec.recordedAt)}</td>
            <td class="cell-wrap" data-label="Tarefa"><strong>${escapeHtml(rec.tarefa || "—")}</strong></td>
            <td class="cell-wrap" data-label="Agendamento">${escapeHtml(rec.agendamento || "—")}</td>
            <td class="mono" data-label="Máquina">${escapeHtml(rec.maquina || "—")}</td>
            <td class="num-col mono" data-label="Código">${escapeHtml(codigoStr)}</td>
            <td data-label="Status"><span class="badge-sm ${stInfo.badge}">${escapeHtml(stInfo.label)}</span></td>
          </tr>
        `;
      })
      .join("");
  }

  function updateBackupLiveStatus(ctx) {
    if (!ctx || !ctx.lastBackupAt) return;
    const ms = Date.parse(ctx.lastBackupAt);
    if (Number.isNaN(ms)) return;

    const warnH = Number(ctx.warnAfterHours) || 24;
    const critH = Number(ctx.criticalAfterHours) || 48;
    const elapsedSec = Math.max(0, Math.floor((Date.now() - ms) / 1000));
    const ageHours = elapsedSec / 3600;
    const isOverdue24h = ageHours >= warnH;
    const isOverdue48h = ageHours >= critH;

    // Idade relativa
    if (el.backupAgeText) {
      el.backupAgeText.textContent = elapsedSec <= 5 ? "Registrado agora mesmo" : `há ${formatDuration(elapsedSec)}`;
    }

    // Status principal e cores
    let badgeClass = "status-online";
    let cardStateClass = "backup-state-ok";
    let navDotClass = "dot-ok";
    let badgeText = (ctx.statusLabel || "SUCESSO").toUpperCase();

    if (ctx.syncRunning) {
      badgeClass = "status-running";
      cardStateClass = "backup-state-running";
      navDotClass = "dot-running";
      badgeText = "SINCRONIZANDO";
    } else if (isOverdue48h) {
      badgeClass = "status-offline";
      cardStateClass = "backup-state-error";
      navDotClass = "dot-err";
      badgeText = `ATRASADO (>${critH}H)`;
    } else if (ctx.level === "error") {
      badgeClass = "status-offline";
      cardStateClass = "backup-state-error";
      navDotClass = "dot-err";
      badgeText = isOverdue24h ? `${badgeText} · >${warnH}H` : badgeText;
    } else if (isOverdue24h) {
      badgeClass = "status-waiting";
      cardStateClass = "backup-state-warn";
      navDotClass = "dot-warn";
      badgeText = `SEM REGISTRO >${warnH}H`;
    } else if (ctx.level === "warn") {
      badgeClass = "status-waiting";
      cardStateClass = "backup-state-warn";
      navDotClass = "dot-warn";
    }

    el.backupStatusBadge.className = `status-badge ${badgeClass}`;
    el.backupStatusText.textContent = badgeText;
    el.backupCard.className = `card backup-card ${cardStateClass}`;
    if (el.navBackupDot) {
      el.navBackupDot.className = `mobile-nav-dot ${navDotClass}`;
    }

    // Barra da janela de 24h / 48h
    if (el.backupFreshnessFill && el.backupFreshnessText) {
      const pct = Math.min(100, Math.max(3, (ageHours / critH) * 100));
      el.backupFreshnessFill.style.width = `${pct.toFixed(1)}%`;
      el.backupFreshnessFill.className = `progress-fill ${isOverdue48h || ctx.level === "error" ? "crit" : isOverdue24h || ctx.level === "warn" ? "warn" : ""}`.trim();

      if (isOverdue48h) {
        el.backupFreshnessText.textContent = `${ageHours.toFixed(1)}h sem registro (acima do limite crítico de ${critH}h)`;
      } else if (isOverdue24h) {
        const remCrit = Math.max(0, critH - ageHours);
        el.backupFreshnessText.textContent = `${ageHours.toFixed(1)}h sem registro (alerta > ${warnH}h · crítico em ${remCrit.toFixed(1)}h)`;
      } else {
        const remWarn = Math.max(0, warnH - ageHours);
        el.backupFreshnessText.textContent = `${ageHours.toFixed(1)}h decorridas · dentro da janela de ${warnH}h (alerta em ${remWarn.toFixed(1)}h)`;
      }
    }

    // Banner superior de alerta se passar de 24h sem registro
    if (el.backupOverdueBanner) {
      if (isOverdue24h) {
        el.backupOverdueBanner.classList.remove("hidden");
        el.backupOverdueBanner.classList.toggle("is-critical", isOverdue48h);
        if (el.backupOverdueTitle) {
          el.backupOverdueTitle.textContent = isOverdue48h
            ? `ALERTA CRÍTICO DE BACKUP — Mais de ${critH}h sem registro`
            : `ALERTA DE BACKUP — Mais de ${warnH}h sem registro`;
        }
        if (el.backupOverdueDesc) {
          el.backupOverdueDesc.textContent = `Último registro em ${formatDateTime(ctx.lastBackupAt)} (tarefa "${ctx.tarefa}", máquina ${ctx.maquina}). Verifique se a rotina de backup está ativa.`;
        }
        if (el.backupOverdueElapsed) {
          el.backupOverdueElapsed.textContent = formatDuration(elapsedSec);
        }
      } else {
        el.backupOverdueBanner.classList.add("hidden");
      }
    }
  }

  // Ticker de tempo a cada 1 segundo (mantém "há Xs", OFFLINE e alerta de 24h do backup sempre vivos)
  function updateTimeTickers() {
    const resp = state.lastResponse;
    if (resp && resp.lastSeenAt) {
      const lastMs = Date.parse(resp.lastSeenAt);
      if (!Number.isNaN(lastMs)) {
        const elapsedSec = Math.max(0, Math.floor((Date.now() - lastMs) / 1000));
        el.lastSyncText.textContent = elapsedSec <= 2 ? "Agora mesmo" : `há ${formatDuration(elapsedSec)}`;

        if (resp.status === "offline") {
          el.offlineElapsed.textContent = formatDuration(elapsedSec);
        }
      }
    } else {
      el.lastSyncText.textContent = "Aguardando...";
    }

    const { api, agent } = getActiveBackupModel();
    const apiHistory = toArray(api?.history);
    if (apiHistory.length > 0) {
      const latest = apiHistory[0];
      const stInfo = mapBackupApiStatus(latest.status);
      updateBackupLiveStatus({
        lastBackupAt: latest.recordedAt,
        level: stInfo.level,
        statusLabel: stInfo.label,
        tarefa: latest.tarefa || "Backup",
        maquina: latest.maquina || "Servidor",
        warnAfterHours: Number(api?.warnAfterHours) || 24,
        criticalAfterHours: Number(api?.criticalAfterHours) || 48,
        syncRunning: Boolean(agent?.syncRunning),
      });
    } else if (agent?.lastBackupAt) {
      updateBackupLiveStatus({
        lastBackupAt: agent.lastBackupAt,
        level: agent.status === "error" ? "error" : agent.status === "warn" ? "warn" : "ok",
        statusLabel: agent.statusLabel || "Em dia",
        tarefa: agent.jobName || "Backup",
        maquina: state.lastResponse?.current?.hostname || "Servidor",
        warnAfterHours: Number(agent.warnAfterHours) || 24,
        criticalAfterHours: Number(agent.criticalAfterHours) || 48,
        syncRunning: Boolean(agent.syncRunning),
      });
    }
  }

  // Polling real da API (/api/backup)
  async function fetchBackupRecords() {
    if (state.demoMode) return;
    try {
      const response = await fetch("/api/backup", { cache: "no-store" });
      if (!response.ok) return;
      const json = deepRepairMojibake(await response.json());
      state.backupApiResponse = json;
      refreshBackupView();
    } catch {
      // Mantém última leitura conhecida
    }
  }

  // Polling real da API (/api/metrics)
  async function fetchLiveMetrics() {
    if (state.demoMode) return;

    try {
      const response = await fetch("/api/metrics", { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const json = deepRepairMojibake(await response.json());
      state.apiUnreachable = false;
      state.lastReceivedLocalTime = Date.now();
      renderDashboard(json);
    } catch (err) {
      state.apiUnreachable = true;
      const fallback = state.lastResponse
        ? { ...state.lastResponse, status: "offline" }
        : {
            status: "offline",
            lastSeenAt: new Date().toISOString(),
            storage: "local-memory",
            current: null,
            history: [],
          };
      renderDashboard(fallback);
    }
  }

  // Gerador de Modo Demo (para pré-visualizar online e offline imediatamente)
  function generateDemoTick() {
    if (!state.demoMode) return;

    if (state.demoOffline) {
      renderDashboard({
        status: "offline",
        serverTime: new Date().toISOString(),
        lastSeenAt: state.demoOfflineSince,
        storage: "demo",
        current: state.demoCurrent,
        history: state.demoHistory,
      });
      return;
    }

    const prevCpu = state.demoHistory.length ? state.demoHistory[state.demoHistory.length - 1].cpu : 26;
    const prevRam = state.demoHistory.length ? state.demoHistory[state.demoHistory.length - 1].ram : 58;
    const cpu = Math.min(96, Math.max(8, Number((prevCpu + (Math.random() - 0.48) * 11).toFixed(1))));
    const ram = Math.min(92, Math.max(40, Number((prevRam + (Math.random() - 0.5) * 3).toFixed(1))));
    const rxBps = Math.round(450_000 + Math.random() * 6_500_000);
    const txBps = Math.round(180_000 + Math.random() * 2_800_000);

    const nowIso = new Date().toISOString();
    const totalRam = 16 * 1024 * 1024 * 1024;
    const usedRam = Math.round(totalRam * (ram / 100));

    state.demoHistory = [...state.demoHistory, { t: nowIso, cpu, ram, rxBps, txBps }].slice(-40);
    state.demoCurrent = {
      serverId: "srv-local",
      hostname: "SRV-LOCAL",
      label: "Servidor Local",
      ip: "192.168.1.100",
      gateway: "192.168.1.1",
      timestamp: nowIso,
      os: {
        caption: "Microsoft Windows 10 Pro",
        version: "10.0.19045",
        architecture: "64-bit",
        lastBoot: new Date(Date.now() - 4 * 86400 * 1000 - 11200 * 1000).toISOString(),
        uptimeSeconds: 4 * 86400 + 11200 + state.demoHistory.length * 3,
      },
      cpu: {
        name: "Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz",
        usagePercent: cpu,
        cores: 8,
        logicalProcessors: 16,
        clockMhz: 2904,
      },
      memory: {
        totalBytes: totalRam,
        usedBytes: usedRam,
        freeBytes: totalRam - usedRam,
        usagePercent: ram,
      },
      disks: [
        { drive: "C:", label: "Sistema", fileSystem: "NTFS", totalBytes: 256e9, usedBytes: 148e9, freeBytes: 108e9, usagePercent: 57.8 },
        { drive: "D:", label: "Dados", fileSystem: "NTFS", totalBytes: 2000e9, usedBytes: 1580e9, freeBytes: 420e9, usagePercent: 79.0 },
        { drive: "E:", label: "Backup_Diario", fileSystem: "NTFS", totalBytes: 1000e9, usedBytes: 410e9, freeBytes: 590e9, usagePercent: 41.0 },
      ],
      network: {
        downloadBps: rxBps,
        uploadBps: txBps,
        totalRxBytes: 48_240_000_000 + state.demoHistory.length * rxBps * 3,
        totalTxBytes: 19_850_000_000 + state.demoHistory.length * txBps * 3,
        adapters: [
          { name: "Ethernet", description: "Intel(R) Gigabit Network", ip: "192.168.1.100", gateway: "192.168.1.1", linkSpeed: "1 Gbps", status: "Up", mac: "3C-7C-3F-A1-08-14" },
        ],
      },
      shares: [
        { name: "Projetos", path: "D:\\Arquivos\\Projetos", description: "Arquivos de projetos ativos", isSystem: false, currentUsers: 3 },
        { name: "Documentos", path: "D:\\Arquivos\\Documentos", description: "Documentos compartilhados", isSystem: false, currentUsers: 1 },
        { name: "Publico", path: "D:\\Compartilhado\\Publico", description: "Troca rápida de arquivos", isSystem: false, currentUsers: 2 },
        { name: "Backups", path: "E:\\Backups", description: "Espelho diário (somente leitura)", isSystem: false, currentUsers: 0 },
        { name: "ADMIN$", path: "C:\\Windows", description: "Administração remota", isSystem: true, currentUsers: 0 },
        { name: "C$", path: "C:\\", description: "Compartilhamento padrão", isSystem: true, currentUsers: 0 },
      ],
      users: {
        totalAccounts: 6,
        enabledAccounts: 5,
        activeSessionsCount: 2,
        smbSessionsCount: 3,
        accounts: [
          { name: "Administrador", fullName: "Admin Servidor", enabled: true, lastLogon: new Date(Date.now() - 3600e3).toISOString(), isActive: true },
          { name: "usuario01", fullName: "Usuário 01", enabled: true, lastLogon: new Date(Date.now() - 1200e3).toISOString(), isActive: true },
          { name: "usuario02", fullName: "Usuário 02", enabled: true, lastLogon: new Date(Date.now() - 600e3).toISOString(), isActive: true },
          { name: "estacao02", fullName: "Estação 02", enabled: true, lastLogon: new Date(Date.now() - 86400e3).toISOString(), isActive: false },
          { name: "backup", fullName: "Conta de Backup", enabled: true, lastLogon: new Date(Date.now() - 25000e3).toISOString(), isActive: false },
          { name: "Convidado", fullName: "Conta Convidado", enabled: false, lastLogon: null, isActive: false },
        ],
        activeSessions: [
          { username: "Administrador", sessionName: "console", state: "Ativo", isActive: true, idleTime: "nenhum", logonTime: "19/11/2026 07:45", source: "Console" },
          { username: "usuario01", sessionName: "rdp-tcp#2", state: "Ativo", isActive: true, idleTime: "2m", logonTime: "19/11/2026 08:20", source: "RDP" },
        ],
        smbSessions: [
          { username: "SRV-LOCAL\\usuario01", clientIp: "192.168.1.50", numOpens: 6, secondsConnected: 2450 },
          { username: "SRV-LOCAL\\usuario02", clientIp: "192.168.1.58", numOpens: 3, secondsConnected: 1120 },
          { username: "SRV-LOCAL\\usuario02", clientIp: "192.168.1.64", numOpens: 1, secondsConnected: 410 },
        ],
      },
      topProcesses: [
        { name: "sqlservr", pid: 2144, memoryBytes: 2_450_000_000, cpuSeconds: 412.2 },
        { name: "chrome", pid: 8820, memoryBytes: 1_320_000_000, cpuSeconds: 195.8 },
        { name: "MsMpEng", pid: 3104, memoryBytes: 420_000_000, cpuSeconds: 98.4 },
        { name: "svchost", pid: 1420, memoryBytes: 265_000_000, cpuSeconds: 44.1 },
        { name: "explorer", pid: 5212, memoryBytes: 198_000_000, cpuSeconds: 21.0 },
        { name: "powershell", pid: 7316, memoryBytes: 115_000_000, cpuSeconds: 12.6 },
      ],
      extras: [
        { id: "svc-LanmanServer", title: "Compartilhamento (SMB)", value: "Em execução", status: "ok", detail: "Serviço Windows: LanmanServer" },
        { id: "svc-TermService", title: "Área de Trabalho Remota", value: "Em execução", status: "ok", detail: "Serviço Windows: TermService" },
        { id: "svc-Spooler", title: "Spooler de Impressão", value: "Em execução", status: "ok", detail: "Serviço Windows: Spooler" },
        { id: "ping-gateway", title: "Ping Gateway", value: `${Math.max(1, Math.round(1 + Math.random() * 2))} ms`, status: "ok", detail: "Destino: 192.168.1.1" },
      ],
      backup: {
        label: "FreeFileSync → OneDrive",
        oneDriveRunning: true,
        syncRunning: false,
        realTimeSyncRunning: false,
      },
      backupApi: {
        ok: true,
        warnAfterHours: 24,
        criticalAfterHours: 48,
        history: [
          { id: "demo-1", recordedAt: new Date(Date.now() - 5 * 3600 * 1000 - 18 * 60 * 1000).toISOString(), tarefa: "Backup_Diario_OneDrive", agendamento: "Diário 02:00", status: "sucesso", codigo: 0, maquina: "SRV-LOCAL" },
          { id: "demo-2", recordedAt: new Date(Date.now() - 29 * 3600 * 1000 - 15 * 60 * 1000).toISOString(), tarefa: "Backup_Diario_OneDrive", agendamento: "Diário 02:00", status: "aviso", codigo: 1, maquina: "SRV-LOCAL" },
          { id: "demo-3", recordedAt: new Date(Date.now() - 53 * 3600 * 1000 - 20 * 60 * 1000).toISOString(), tarefa: "Backup_Diario_OneDrive", agendamento: "Diário 02:00", status: "sucesso", codigo: 0, maquina: "SRV-LOCAL" },
          { id: "demo-4", recordedAt: new Date(Date.now() - 77 * 3600 * 1000 - 14 * 60 * 1000).toISOString(), tarefa: "Backup_Diario_OneDrive", agendamento: "Manual", status: "cancelado", codigo: 3, maquina: "SRV-LOCAL" },
        ],
      },
    };

    renderDashboard({
      status: "online",
      serverTime: nowIso,
      lastSeenAt: nowIso,
      storage: "demo",
      current: state.demoCurrent,
      history: state.demoHistory,
    });
  }

  function setDemoMode(enabled) {
    state.demoMode = enabled;
    state.demoOffline = false;
    el.btnDemoToggle.classList.toggle("active", enabled);
    el.btnDemoToggle.textContent = enabled ? "Sair do Demo" : "Modo Demo";
    el.demoPill.classList.toggle("hidden", !enabled);
    el.btnSimulateOffline.classList.toggle("hidden", !enabled);
    el.btnSimulateOffline.classList.remove("active");
    el.btnSimulateOffline.textContent = "Simular Offline";

    if (enabled) {
      if (state.demoHistory.length === 0) {
        // Preenche 12 pontos iniciais para os gráficos já aparecerem bonitos
        for (let i = 0; i < 12; i++) generateDemoTick();
      } else {
        generateDemoTick();
      }
      showToast("Modo Demo ativado (dados simulados).");
    } else {
      fetchLiveMetrics();
      fetchBackupRecords();
      showToast("Voltando para dados reais do servidor.");
    }
  }

  // Eventos de UI
  el.btnDemoToggle.addEventListener("click", () => setDemoMode(!state.demoMode));
  el.btnWaitingDemo.addEventListener("click", () => setDemoMode(true));

  el.btnSimulateOffline.addEventListener("click", () => {
    if (!state.demoMode) return;
    state.demoOffline = !state.demoOffline;
    if (state.demoOffline) {
      state.demoOfflineSince = new Date(Date.now() - 25_000).toISOString();
      el.btnSimulateOffline.textContent = "Voltar Online";
      el.btnSimulateOffline.classList.add("active");
    } else {
      el.btnSimulateOffline.textContent = "Simular Offline";
      el.btnSimulateOffline.classList.remove("active");
    }
    generateDemoTick();
  });

  el.toggleSystemShares.addEventListener("change", (e) => {
    state.showSystemShares = e.target.checked;
    if (state.lastResponse?.current) {
      renderShares(
        toArray(state.lastResponse.current.shares),
        state.lastResponse.current.ip || state.lastResponse.current.hostname
      );
    }
  });

  document.querySelectorAll("[data-users-tab]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const tab = btn.getAttribute("data-users-tab");
      state.activeUsersTab = tab;
      document.querySelectorAll("[data-users-tab]").forEach((b) => b.classList.toggle("active", b === btn));
      el.tabUsersActive.classList.toggle("hidden", tab !== "active");
      el.tabUsersAll.classList.toggle("hidden", tab !== "all");
    });
  });

  async function copyTextToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch {
        // Fallback para HTTP na rede local
      }
    }
    try {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.left = "-9999px";
      ta.style.top = "0";
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      const ok = document.execCommand("copy");
      document.body.removeChild(ta);
      return ok;
    } catch {
      return false;
    }
  }

  document.addEventListener("click", (e) => {
    const copyBtn = e.target.closest("[data-copy-unc]");
    if (!copyBtn) return;
    const unc = copyBtn.getAttribute("data-copy-unc");
    copyTextToClipboard(unc).then((copied) => {
      showToast(copied ? `Caminho copiado: ${unc}` : `Caminho UNC: ${unc}`);
    });
  });

  function triggerManualRefresh(btn) {
    if (btn) {
      btn.classList.remove("is-spinning");
      void btn.offsetWidth;
      btn.classList.add("is-spinning");
      setTimeout(() => btn.classList.remove("is-spinning"), 650);
    }
    if (state.demoMode) {
      generateDemoTick();
      showToast("Dados simulados atualizados.");
    } else {
      Promise.all([fetchLiveMetrics(), fetchBackupRecords()]).then(() => showToast("Telemetria e backup atualizados."));
    }
  }

  if (el.btnManualRefresh) {
    el.btnManualRefresh.addEventListener("click", () => triggerManualRefresh(el.btnManualRefresh));
  }
  if (el.btnStickyRefresh) {
    el.btnStickyRefresh.addEventListener("click", () => triggerManualRefresh(el.btnStickyRefresh));
  }

  el.btnSetupGuide.addEventListener("click", () => el.setupModal.classList.remove("hidden"));
  el.btnCloseModal.addEventListener("click", () => el.setupModal.classList.add("hidden"));
  el.setupModal.addEventListener("click", (e) => {
    if (e.target === el.setupModal) el.setupModal.classList.add("hidden");
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !el.setupModal.classList.contains("hidden")) {
      el.setupModal.classList.add("hidden");
    }
  });

  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    if (el.metaThemeColor) {
      el.metaThemeColor.setAttribute("content", theme === "light" ? "#f1f5f9" : "#0b0f17");
    }
  }

  el.btnThemeToggle.addEventListener("click", () => {
    const html = document.documentElement;
    const next = html.getAttribute("data-theme") === "dark" ? "light" : "dark";
    applyTheme(next);
    localStorage.setItem("server-monitor-theme", next);
  });

  const savedTheme = localStorage.getItem("server-monitor-theme");
  if (savedTheme === "light" || savedTheme === "dark") {
    applyTheme(savedTheme);
  }

  // Navegação e barra fixa superior para celular (scroll-spy sem ocultar nenhuma seção)
  const navLinks = Array.from(document.querySelectorAll(".mobile-nav-item[data-nav-target]"));
  const navSections = navLinks
    .map((link) => ({
      id: link.getAttribute("data-nav-target"),
      link,
      section: document.getElementById(link.getAttribute("data-nav-target")),
    }))
    .filter((item) => item.section);

  let scrollTicking = false;
  function updateMobileNavigation() {
    scrollTicking = false;
    const isMobile = window.innerWidth <= 768;

    if (el.mobileStickyBar && el.mainTopbar) {
      const topbarRect = el.mainTopbar.getBoundingClientRect();
      const shouldShowSticky = isMobile && topbarRect.bottom < 12;
      el.mobileStickyBar.classList.toggle("is-visible", shouldShowSticky);
      el.mobileStickyBar.setAttribute("aria-hidden", shouldShowSticky ? "false" : "true");
    }

    if (!isMobile || navSections.length === 0) return;

    const scrollBottom = window.scrollY + window.innerHeight;
    const docHeight = document.documentElement.scrollHeight;
    let activeId = navSections[0].id;

    if (docHeight - scrollBottom < 48) {
      activeId = navSections[navSections.length - 1].id;
    } else {
      const threshold = 110;
      for (const item of navSections) {
        const rect = item.section.getBoundingClientRect();
        if (rect.top <= threshold) {
          activeId = item.id;
        }
      }
    }

    navSections.forEach((item) => {
      item.link.classList.toggle("active", item.id === activeId);
    });
  }

  function scheduleMobileNavUpdate() {
    if (!scrollTicking) {
      scrollTicking = true;
      window.requestAnimationFrame(updateMobileNavigation);
    }
  }

  window.addEventListener("scroll", scheduleMobileNavUpdate, { passive: true });
  window.addEventListener("resize", scheduleMobileNavUpdate, { passive: true });

  navLinks.forEach((link) => {
    link.addEventListener("click", (e) => {
      const targetId = link.getAttribute("data-nav-target");
      const target = document.getElementById(targetId);
      if (!target) return;
      e.preventDefault();
      const stickyOffset = window.innerWidth <= 768 ? 64 : 16;
      const targetTop = target.getBoundingClientRect().top + window.scrollY - stickyOffset;
      window.scrollTo({ top: Math.max(0, targetTop), behavior: "smooth" });
      navLinks.forEach((l) => l.classList.toggle("active", l === link));
    });
  });

  // Atualiza imediatamente ao voltar para o app/aba no celular
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      updateTimeTickers();
      if (!state.demoMode) {
        fetchLiveMetrics();
        fetchBackupRecords();
      }
    }
  });

  // Inicialização
  updateMobileNavigation();
  fetchLiveMetrics();
  fetchBackupRecords();
  setInterval(() => {
    if (state.demoMode) generateDemoTick();
    else {
      fetchLiveMetrics();
      fetchBackupRecords();
    }
  }, POLL_INTERVAL_MS);

  setInterval(updateTimeTickers, 1000);
})();
