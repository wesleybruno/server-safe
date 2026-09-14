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

function unlock(stepSel, btnSel) {
  $(stepSel).classList.remove("disabled");
  if (btnSel) $(btnSel).disabled = false;
}

function unlockSSHStep() {
  unlock("#step-ssh", "#btn-harden-ssh");
}

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

      if (outcome.key_token) {
        $("#u-download").classList.remove("hidden");
        $("#u-download-link").href = "/download/key/" + outcome.key_token;
        $("#u-fingerprint").textContent = (outcome.result.data && outcome.result.data.fingerprint) || "";
        $("#u-confirm-download").addEventListener("change", (e) => {
          if (e.target.checked) unlockSSHStep();
        });
      } else {
        unlockSSHStep();
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
        unlock("#step-firewall", "#btn-firewall");
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
      if (result.status === "ok") unlock("#step-fail2ban", "#btn-fail2ban");
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
      if (result.status === "ok") unlock("#step-updates", "#btn-updates");
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
      if (result.status === "ok") unlock("#step-timers", null);
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

$("#btn-continue-timers").addEventListener("click", () => {
  unlock("#step-audit", "#btn-audit");
});

$("#btn-audit").addEventListener("click", async () => {
  const portVal = $("#au-ssh-port").value.trim();
  const body = {};
  if (portVal) body.ssh_port = parseInt(portVal, 10);

  const log = $("#au-log");
  const report = $("#au-report");
  log.textContent = "";
  report.textContent = "";
  $("#btn-audit").disabled = true;

  await streamRequest(
    "/api/audit/run",
    body,
    (line) => appendLog(log, line),
    (result) => {
      appendLog(log, "== resultado: " + result.status + " - " + result.detail);
      if (result.data && result.data.report) report.textContent = result.data.report;
      $("#btn-audit").disabled = false;
      unlock("#step-cleanup", "#btn-cleanup");
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
