(() => {
  const NEXT = { todo: "in_progress", in_progress: "done" };
  const PREV = { in_progress: "todo", done: "in_progress" };
  const message = document.getElementById("message");

  const api = async (path, options = {}) => {
    const response = await fetch(path, {
      headers: { "Content-Type": "application/json" },
      ...options,
    });
    if (response.status === 204) return null;
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error || `Request failed (${response.status})`);
    return body;
  };

  const show = (text) => { message.textContent = text || ""; };

  const card = (task) => {
    const li = document.createElement("li");
    li.className = `card ${task.priority}`;

    const title = document.createElement("div");
    title.className = "title";
    title.textContent = task.title; // textContent: never inject user input as HTML
    li.appendChild(title);

    const actions = document.createElement("div");
    actions.className = "actions";
    const add = (label, handler, cls = "") => {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = label;
      if (cls) button.className = cls;
      button.addEventListener("click", handler);
      actions.appendChild(button);
    };
    if (PREV[task.status]) add("←", () => move(task, PREV[task.status]));
    if (NEXT[task.status]) add("→", () => move(task, NEXT[task.status]));
    add("delete", () => remove(task), "danger");
    li.appendChild(actions);
    return li;
  };

  const render = (tasks) => {
    document.querySelectorAll(".column").forEach((column) => {
      const status = column.dataset.status;
      const list = column.querySelector("ul");
      const items = tasks.filter((task) => task.status === status);
      list.replaceChildren(...items.map(card));
      document.getElementById(`count-${status}`).textContent = items.length;
    });
  };

  const load = async () => {
    try {
      render(await api("/api/tasks"));
      show("");
    } catch (error) {
      show(error.message);
    }
  };

  const move = async (task, status) => {
    try { await api(`/api/tasks/${task.id}`, { method: "PUT", body: JSON.stringify({ status }) }); await load(); }
    catch (error) { show(error.message); }
  };

  const remove = async (task) => {
    try { await api(`/api/tasks/${task.id}`, { method: "DELETE" }); await load(); }
    catch (error) { show(error.message); }
  };

  document.getElementById("task-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.target;
    const payload = { title: form.title.value.trim(), priority: form.priority.value };
    try {
      await api("/api/tasks", { method: "POST", body: JSON.stringify(payload) });
      form.reset();
      await load();
    } catch (error) {
      show(error.message);
    }
  });

  const checkDatabase = async () => {
    const label = document.getElementById("db-state");
    try {
      const response = await fetch("/health/ready");
      label.textContent = response.ok ? "database: up" : "database: unreachable";
    } catch {
      label.textContent = "database: unreachable";
    }
  };

  load();
  checkDatabase();
  setInterval(checkDatabase, 15000);
})();
