const $ = (sel) => document.querySelector(sel);

// Reads a fetch() response body as newline-delimited JSON events, so a
// single POST can stream live script output without a separate SSE/job
// endpoint (EventSource can't do POST; ReadableStream can).
async function streamRequest(url, body, onLine, onResult, onError) {
  let res;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch (e) {
    onError(String(e));
    return;
  }
  if (!res.ok || !res.body) {
    onError(await res.text());
    return;
  }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    let idx;
    while ((idx = buf.indexOf("\n")) >= 0) {
      const raw = buf.slice(0, idx);
      buf = buf.slice(idx + 1);
      if (!raw.trim()) continue;
      const ev = JSON.parse(raw);
      if (ev.type === "log") onLine(ev.line);
      else if (ev.type === "result") onResult(ev.result);
      else if (ev.type === "error") onError(ev.error);
    }
  }
}

function appendLog(el, line) {
  el.textContent += line + "\n";
  el.scrollTop = el.scrollHeight;
}

// Todas as etapas ficam sempre navegaveis e clicaveis — nao ha mais trava
// client-side. Etapas com dependencia real de uma anterior mostram um
// aviso (.warn) no proprio painel, e o backend confere de verdade na hora
// de executar (ex: ssh-harden.sh recusa desativar senha sem chave
// instalada; firewall-ufw.sh recusa sem sshd escutando na porta nova;
// portainer/traefik recusam sem Docker instalado) — a UI so orienta,
// quem garante e o script.
function selectStep(stepSel) {
  const panel = $(stepSel);
  if (!panel) return;
  document.querySelectorAll("main .step").forEach((p) => p.classList.remove("active"));
  panel.classList.add("active");
  document.querySelectorAll("#step-nav button").forEach((b) => {
    b.classList.toggle("active", "#" + b.dataset.target === stepSel);
  });
}


// Nav a esquerda gerado a partir dos proprios steps (id + texto do h2) em
// vez de duplicado no HTML — um so lugar pra manter em dia.
function buildStepNav() {
  const nav = $("#step-nav");
  const panels = document.querySelectorAll("main .step");
  panels.forEach((panel) => {
    const h2 = panel.querySelector("h2");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = h2 ? h2.textContent : panel.id;
    btn.dataset.target = panel.id;
    btn.addEventListener("click", () => selectStep("#" + panel.id));
    nav.appendChild(btn);
  });
  if (panels[0]) selectStep("#" + panels[0].id);
}

buildStepNav();

const EXTRAS = {
  docker: "/api/extras/docker",
  portainer: "/api/extras/portainer",
  traefik: "/api/extras/traefik",
  coolify: "/api/extras/coolify",
  easypanel: "/api/extras/easypanel",
  cpanel: "/api/extras/cpanel",
};

const STEP_LABELS = {
  users: "Usuario e chave SSH",
  ssh: "Hardening SSH",
  firewall: "Firewall (UFW)",
  fail2ban: "Fail2ban",
  updates: "Atualizacoes automaticas",
  timers: "Timers de app",
  audit: "Auditoria final",
  cleanup: "Limpeza final",
};

// Os extras (Docker/Portainer/...) nao aparecem no checklist do dashboard —
// sao muitos e opcionais, o status de cada um fica so no proprio card na
// aba "Libs extras" (setExtraStatuses): um check ao lado do nome quando
// instalado, nada quando nao — sem badge/texto "nao instalado" poluindo.
function setExtraStatuses(done) {
  Object.keys(EXTRAS).forEach((key) => {
    const check = $("#ex-" + key + "-check");
    if (check) check.hidden = !done["extras_" + key];
  });
}

function setGauge(prefix, pct) {
  const val = typeof pct === "number" ? pct : parseFloat(pct);
  const fill = $("#db-" + prefix + "-fill");
  const label = $("#db-" + prefix + "-val");
  if (!isFinite(val)) {
    label.textContent = "--";
    return;
  }
  label.textContent = val.toFixed(1) + "%";
  fill.style.width = Math.min(100, Math.max(0, val)) + "%";
  fill.classList.toggle("warn", val >= 70 && val < 90);
  fill.classList.toggle("crit", val >= 90);
}

async function refreshDashboard() {
  let data;
  try {
    const res = await fetch("/api/dashboard");
    if (!res.ok) return;
    data = await res.json();
  } catch {
    return;
  }

  document.title = "server-safe " + (data.version || "dev");
  $("#app-version").textContent = data.version || "dev";

  setGauge("cpu", data.stats && data.stats.cpu_percent);
  setGauge("mem", data.stats && data.stats.mem_percent);
  setGauge("disk", data.stats && data.stats.disk_percent);

  const done = data.steps || {};

  const list = $("#db-steps");
  const order = (data.steps_order || []).filter((step) => !step.startsWith("extras_"));
  list.innerHTML = order
    .map((step) => {
      const label = STEP_LABELS[step] || step;
      return `<li class="${done[step] ? "done" : ""}">${label}</li>`;
    })
    .join("");

  setExtraStatuses(done);
}

refreshDashboard();
setInterval(refreshDashboard, 3000);

$("#u-password-copy").addEventListener("click", async () => {
  const input = $("#u-password-value");
  input.select();
  try {
    await navigator.clipboard.writeText(input.value);
    const btn = $("#u-password-copy");
    const original = btn.textContent;
    btn.textContent = "copiado!";
    setTimeout(() => { btn.textContent = original; }, 1500);
  } catch {
    // clipboard API pode falhar (permissao/contexto) — o input.select() acima
    // ja deixa o valor selecionado pra copiar na mao (Ctrl+C).
  }
});

document.querySelectorAll('input[name="key-mode"]').forEach((r) => {
  r.addEventListener("change", () => {
    const importing = document.querySelector('input[name="key-mode"]:checked').value === "import";
    $("#u-pubkey").classList.toggle("hidden", !importing);
  });
});

$("#btn-create-user").addEventListener("click", async () => {
  const username = $("#u-username").value.trim();
  if (!username) { alert("informe o usuario"); return; }
  const mode = document.querySelector('input[name="key-mode"]:checked').value;
  const body = { username, generate_key: mode === "generate" };
  if (mode === "import") body.public_key = $("#u-pubkey").value.trim();

  const log = $("#u-log");
  log.textContent = "";
  $("#btn-create-user").disabled = true;

  await streamRequest(
    "/api/users/create",
    body,
    (line) => appendLog(log, line),
    (outcome) => {
      appendLog(log, "== resultado: " + outcome.result.status + " - " + outcome.result.detail);
      $("#btn-create-user").disabled = false;
      if (outcome.result.status !== "ok") return;

      const password = outcome.result.data && outcome.result.data.password;
      if (password) {
        $("#u-password-box").classList.remove("hidden");
        $("#u-password-value").value = password;
      }

      if (outcome.key_token) {
        $("#u-download").classList.remove("hidden");
        $("#u-download-link").href = "/download/key/" + outcome.key_token;
        $("#u-fingerprint").textContent = (outcome.result.data && outcome.result.data.fingerprint) || "";
      }
    },
    (err) => {
      appendLog(log, "ERRO: " + err);
      $("#btn-create-user").disabled = false;
    }
  );
});

$("#btn-harden-ssh").addEventListener("click", async () => {
  const port = parseInt($("#s-port").value, 10);
  const body = {
    port,
    disable_password: $("#s-disable-password").checked,
    disable_root: $("#s-disable-root").checked,
  };
  const log = $("#s-log");
  log.textContent = "";
  $("#btn-harden-ssh").disabled = true;

  await streamRequest(
    "/api/ssh/harden",
    body,
    (line) => appendLog(log, line),
    (result) => {
      appendLog(log, "== resultado: " + result.status + " - " + result.detail);
      $("#btn-harden-ssh").disabled = false;
      if (result.status === "ok") {
        // propaga a porta escolhida para os steps seguintes que dependem dela
        ["#fw-ssh-port", "#f2b-ssh-port", "#au-ssh-port"].forEach((sel) => ($(sel).value = port));
      }
    },
    (err) => {
      appendLog(log, "ERRO: " + err);
      $("#btn-harden-ssh").disabled = false;
    }
  );
});

$("#btn-firewall").addEventListener("click", async () => {
  const body = {
    ssh_port: parseInt($("#fw-ssh-port").value, 10),
    extra_ports: $("#fw-extra-ports").value.trim(),
  };
  const log = $("#fw-log");
  log.textContent = "";
  $("#btn-firewall").disabled = true;

  await streamRequest(
    "/api/firewall/enable",
    body,
    (line) => appendLog(log, line),
    (result) => {
      appendLog(log, "== resultado: " + result.status + " - " + result.detail);
      $("#btn-firewall").disabled = false;
    },
    (err) => {
      appendLog(log, "ERRO: " + err);
      $("#btn-firewall").disabled = false;
    }
  );
});

$("#btn-fail2ban").addEventListener("click", async () => {
  const body = {
    ssh_port: parseInt($("#f2b-ssh-port").value, 10),
    ban_time: parseInt($("#f2b-bantime").value, 10),
    find_time: parseInt($("#f2b-findtime").value, 10),
    max_retry: parseInt($("#f2b-maxretry").value, 10),
  };
  const log = $("#f2b-log");
  log.textContent = "";
  $("#btn-fail2ban").disabled = true;

  await streamRequest(
    "/api/fail2ban/enable",
    body,
    (line) => appendLog(log, line),
    (result) => {
      appendLog(log, "== resultado: " + result.status + " - " + result.detail);
      $("#btn-fail2ban").disabled = false;
    },
    (err) => {
      appendLog(log, "ERRO: " + err);
      $("#btn-fail2ban").disabled = false;
    }
  );
});

$("#btn-updates").addEventListener("click", async () => {
  const body = {
    auto_reboot: $("#upd-auto-reboot").checked,
    reboot_time: $("#upd-reboot-time").value.trim(),
  };
  const log = $("#upd-log");
  log.textContent = "";
  $("#btn-updates").disabled = true;

  await streamRequest(
    "/api/updates/enable",
    body,
    (line) => appendLog(log, line),
    (result) => {
      appendLog(log, "== resultado: " + result.status + " - " + result.detail);
      $("#btn-updates").disabled = false;
    },
    (err) => {
      appendLog(log, "ERRO: " + err);
      $("#btn-updates").disabled = false;
    }
  );
});

$("#btn-add-timer").addEventListener("click", async () => {
  const body = {
    name: $("#tm-name").value.trim(),
    command: $("#tm-command").value.trim(),
    on_calendar: $("#tm-calendar").value.trim(),
  };
  if (!body.name || !body.command || !body.on_calendar) {
    alert("preencha nome, comando e agenda");
    return;
  }
  const log = $("#tm-log");
  $("#btn-add-timer").disabled = true;

  await streamRequest(
    "/api/timers/create",
    body,
    (line) => appendLog(log, line),
    (result) => {
      appendLog(log, "== resultado: " + result.status + " - " + result.detail);
      $("#btn-add-timer").disabled = false;
    },
    (err) => {
      appendLog(log, "ERRO: " + err);
      $("#btn-add-timer").disabled = false;
    }
  );
});

function wireExtraInstall(key, url) {
  const btn = $("#btn-install-" + key);
  const log = $("#ex-" + key + "-log");
  btn.addEventListener("click", async () => {
    log.textContent = "";
    btn.disabled = true;

    await streamRequest(
      url,
      {},
      (line) => appendLog(log, line),
      (result) => {
        appendLog(log, "== resultado: " + result.status + " - " + result.detail);
        btn.disabled = false;
        // atualizacao otimista — o proximo poll do dashboard (ate 3s) confirma.
        // Portainer/Traefik/Coolify/EasyPanel instalam o Docker junto se
        // precisar, entao o check do Docker acompanha o deles tambem.
        if (result.status === "ok") {
          const dependsOnDocker = ["portainer", "traefik", "coolify", "easypanel"];
          const keys = dependsOnDocker.includes(key) ? [key, "docker"] : [key];
          keys.forEach((k) => {
            const check = $("#ex-" + k + "-check");
            if (check) check.hidden = false;
          });
        }
      },
      (err) => {
        appendLog(log, "ERRO: " + err);
        btn.disabled = false;
      }
    );
  });
}

Object.entries(EXTRAS).forEach(([key, url]) => wireExtraInstall(key, url));

// Unicos lugares que trocam de etapa por conta propria: o usuario clicou
// num botao "continuar" explicito, o que conta como ele escolhendo
// avancar — diferente do resultado de uma acao (aplicar/ativar/rodar), que
// nunca deve navegar sozinho (so o usuario troca de etapa pelo menu).
$("#btn-continue-timers").addEventListener("click", () => {
  selectStep("#step-extras");
});

$("#btn-continue-extras").addEventListener("click", () => {
  selectStep("#step-audit");
});

// Report do backend e texto plano, uma linha por checagem:
// "[ok|warn|fail] label - detalhe" (+ secao solta do lynis no fim, que nao
// bate no formato e fica de fora do resumo, so aparece no relatorio
// completo). Monta o resumo (falhas/alertas) a partir dai.
function renderAuditList(el, items) {
  el.innerHTML = "";
  items.forEach((item) => {
    const li = document.createElement("li");
    const strong = document.createElement("strong");
    strong.textContent = item.label;
    li.appendChild(strong);
    li.appendChild(document.createTextNode(" — " + item.detail));
    el.appendChild(li);
  });
}

function renderAuditSummary(data) {
  const report = (data && data.report) || "";
  const fails = [];
  const warns = [];
  report.split("\n").forEach((line) => {
    const m = line.match(/^\[(ok|warn|fail)\]\s+(\S+)\s+-\s+(.*)$/);
    if (!m) return;
    const [, status, label, detail] = m;
    if (status === "fail") fails.push({ label, detail });
    else if (status === "warn") warns.push({ label, detail });
  });

  $("#au-count-ok").textContent = (data && data.pass) || 0;
  $("#au-count-warn").textContent = (data && data.warn) || 0;
  $("#au-count-fail").textContent = (data && data.fail) || 0;

  renderAuditList($("#au-fails"), fails);
  renderAuditList($("#au-warns"), warns);
  $("#au-clean").classList.toggle("hidden", fails.length + warns.length > 0);
  $("#au-report").textContent = report;
  $("#au-summary").classList.remove("hidden");
}

$("#btn-audit").addEventListener("click", async () => {
  const portVal = $("#au-ssh-port").value.trim();
  const body = {};
  if (portVal) body.ssh_port = parseInt(portVal, 10);

  const log = $("#au-log");
  log.textContent = "";
  $("#au-summary").classList.add("hidden");
  $("#btn-audit").disabled = true;

  await streamRequest(
    "/api/audit/run",
    body,
    (line) => appendLog(log, line),
    (result) => {
      appendLog(log, "== resultado: " + result.status + " - " + result.detail);
      renderAuditSummary(result.data);
      $("#btn-audit").disabled = false;
    },
    (err) => {
      appendLog(log, "ERRO: " + err);
      $("#btn-audit").disabled = false;
    }
  );
});

$("#btn-cleanup").addEventListener("click", async () => {
  const pathsRaw = $("#cl-paths").value.trim();
  const body = {
    delay: $("#cl-delay").value,
    paths: pathsRaw ? pathsRaw.split(",").map((p) => p.trim()).filter(Boolean) : [],
    self_destruct: $("#cl-self-destruct").checked,
  };
  const log = $("#cl-log");
  log.textContent = "";
  $("#btn-cleanup").disabled = true;

  await streamRequest(
    "/api/cleanup/schedule",
    body,
    (line) => appendLog(log, line),
    (result) => {
      appendLog(log, "== resultado: " + result.status + " - " + result.detail);
      appendLog(log, "wizard concluido — este painel vai se desligar sozinho em breve.");
    },
    (err) => {
      appendLog(log, "ERRO: " + err);
      $("#btn-cleanup").disabled = false;
    }
  );
});
