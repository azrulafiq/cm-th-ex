// from task 2 - app page logic: health polling, load balancing view, db query, chaos buttons
(function () {
  const $ = (id) => document.getElementById(id);
  const served = {};
  const logRows = [];
  let timer = null;

  // stable color per version so v1/v2/v3 look different during a rolling update
  function versionColor(v) {
    let h = 0;
    for (const c of v) h = (h * 31 + c.charCodeAt(0)) % 360;
    return `hsl(${h}, 65%, 48%)`;
  }

  async function call(path, opts = {}) {
    const start = performance.now();
    let status = 0;
    let data = null;
    try {
      const res = await fetch(path, { cache: "no-store", ...opts });
      status = res.status;
      data = await res.json().catch(() => null);
    } catch (e) {
      data = { error: String(e) };
    }
    const ms = Math.round(performance.now() - start);
    addLog(opts.method || "GET", path, status, ms, data && data.pod);
    return { ok: status >= 200 && status < 300, status, data, ms };
  }

  function setCheck(id, r) {
    const el = $(id);
    el.classList.toggle("ok", r.ok);
    el.classList.toggle("bad", !r.ok);
    el.querySelector(".ms").textContent = r.status ? `${r.status} / ${r.ms} ms` : "down";
  }

  function addLog(method, path, status, ms, pod) {
    logRows.unshift({ t: new Date().toLocaleTimeString(), method, path, status, ms, pod: pod || "" });
    logRows.length = Math.min(logRows.length, 15);
    const body = $("log-body");
    body.replaceChildren(
      ...logRows.map((r) => {
        const tr = document.createElement("tr");
        const cells = [r.t, `${r.method} ${r.path}`, r.status || "err", r.ms, r.pod];
        cells.forEach((v, i) => {
          const td = document.createElement("td");
          td.textContent = v;
          if (i === 2) td.className = "s" + String(r.status)[0];
          tr.appendChild(td);
        });
        return tr;
      })
    );
  }

  function renderBars() {
    const entries = Object.entries(served).sort((a, b) => b[1].count - a[1].count);
    const total = entries.reduce((s, [, v]) => s + v.count, 0);
    $("lb-bars").replaceChildren(
      ...entries.map(([pod, v]) => {
        const row = document.createElement("div");
        row.className = "bar-row";
        const name = document.createElement("span");
        name.className = "name";
        name.textContent = `${pod}  (${v.version})`;
        const count = document.createElement("span");
        count.className = "count";
        count.textContent = `${v.count}  ${Math.round((v.count / total) * 100)}%`;
        const track = document.createElement("div");
        track.className = "bar-track";
        const fill = document.createElement("div");
        fill.className = "bar-fill";
        fill.style.width = `${(v.count / total) * 100}%`;
        fill.style.background = versionColor(v.version);
        track.appendChild(fill);
        row.append(name, count, track);
        return row;
      })
    );
    $("lb-total").textContent = `${total} requests`;
  }

  async function refresh() {
    const [live, ready, info] = await Promise.all([call("/healthz"), call("/readyz"), call("/api/info")]);
    setCheck("chk-healthz", live);
    setCheck("chk-readyz", ready);
    setCheck("chk-info", info);
    if (info.ok && info.data) {
      const { pod, version } = info.data;
      served[pod] = served[pod] || { count: 0, version };
      served[pod].count += 1;
      served[pod].version = version;
      $("current-pod").textContent = pod;
      const badge = $("version-badge");
      badge.textContent = version;
      badge.style.background = versionColor(version);
      renderBars();
    }
  }

  async function runDb() {
    const btn = $("run-db");
    btn.disabled = true;
    const r = await call("/db");
    btn.disabled = false;
    const d = r.data || {};
    $("db-status").textContent = r.ok ? `ok (${r.ms} ms)` : `error ${r.status}: ${d.error || ""}`;
    $("db-version").textContent = d.db_version ? d.db_version.split(" on ")[0] : "-";
    $("db-time").textContent = d.db_time || "-";
    $("db-visits").textContent = d.visits ?? "-";
    $("db-conns").textContent = d.db_connections ?? "-";
    $("db-pod").textContent = d.pod || "-";
  }

  async function chaos(path, btn) {
    const token = $("token").value.trim();
    if (!token) {
      $("token").focus();
      return;
    }
    btn.disabled = true;
    await call(path, { headers: { "X-Chaos-Token": token } });
    btn.disabled = false;
  }

  function setAuto(on) {
    clearInterval(timer);
    if (on) timer = setInterval(refresh, 3000);
  }

  document.querySelectorAll("[data-chaos]").forEach((b) => b.addEventListener("click", () => chaos(b.dataset.chaos, b)));
  $("run-db").addEventListener("click", runDb);
  $("auto").addEventListener("change", (e) => setAuto(e.target.checked));
  $("reset-lb").addEventListener("click", () => {
    for (const k of Object.keys(served)) delete served[k];
    renderBars();
  });
  $("clear-log").addEventListener("click", () => {
    logRows.length = 0;
    $("log-body").replaceChildren();
  });

  $("version-badge").style.background = versionColor(document.body.dataset.version);
  refresh();
  runDb();
  setAuto(true);
})();
