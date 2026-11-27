const editor = document.querySelector("#skill-demo");

if (editor) {
  const blocks = {
    attack: { slot: "trigger", label: "攻击时", style: "trigger" },
    turn: { slot: "trigger", label: "回合开始时", style: "trigger" },
    threshold: { slot: "condition", label: "对手生命不高于", style: "condition", min: 0, max: 30 },
    damage: { slot: "effects", label: "对手受到伤害", style: "damage", min: 1, max: 9 },
    heal: { slot: "effects", label: "我方恢复生命", style: "heal", min: 1, max: 9 },
    draw: { slot: "effects", label: "我方抽牌", style: "draw", min: 1, max: 9 },
  };
  const initial = { self: 24, opponent: 22, draw: 0 };
  const emptySkill = () => ({ trigger: null, condition: null, effects: [] });
  const slots = Object.fromEntries([...editor.querySelectorAll("[data-slot]")].map(slot => [slot.dataset.slot, slot]));
  const output = Object.fromEntries([...editor.querySelectorAll("[data-stat]")].map(stat => [stat.dataset.stat, stat.querySelector("output")]));
  const status = editor.querySelector(".demo-message");
  const log = editor.querySelector(".demo-log");
  const result = editor.querySelector("#demo-result-title");
  const clearButton = editor.querySelector('[data-demo-command="clear"]');
  let skill = emptySkill();
  let dragging = null;

  function showStatus(message = "") {
    status.textContent = message;
  }

  function showResult(stats, steps = []) {
    for (const [name, value] of Object.entries(stats)) {
      if (output[name].textContent !== String(value)) output[name].textContent = value;
    }
    log.replaceChildren(...steps.map(step => {
      const line = document.createElement("li");
      line.textContent = step;
      return line;
    }));
  }

  function refreshSkill(message = "") {
    showResult(initial);
    showStatus(message);
    renderSkill();
  }

  function actionButton(caption, accessibleName, handler) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "demo-block-action";
    button.textContent = caption;
    button.setAttribute("aria-label", accessibleName);
    button.addEventListener("click", handler);
    return button;
  }

  function blockRow(block, removeBlock, index = null) {
    const { label, style, min, max } = blocks[block.id];
    const row = document.createElement("div");
    row.className = "demo-block demo-work-block " + style;
    row.dataset.blockId = block.id;
    const text = document.createElement("span");
    text.textContent = label;
    row.append(text);
    if (min !== undefined) {
      const amount = document.createElement("input");
      amount.type = "number";
      amount.min = min;
      amount.max = max;
      amount.step = 1;
      amount.inputMode = "numeric";
      amount.value = block.amount ?? "";
      amount.setAttribute("aria-label", label + "的数值");
      amount.addEventListener("input", () => {
        block.amount = amount.value === "" ? null : amount.valueAsNumber;
        showStatus();
        showResult(initial);
      });
      row.append(amount);
    }

    const tools = document.createElement("div");
    tools.className = "demo-block-tools";
    if (index !== null) {
      for (const [offset, icon, name] of [[-1, "↑", "上移"], [1, "↓", "下移"]]) {
        const destination = index + offset;
        const move = actionButton(icon, name + label, () => {
          [skill.effects[index], skill.effects[destination]] = [skill.effects[destination], skill.effects[index]];
          refreshSkill(name + "了「" + label + "」。");
          slots.effects.querySelectorAll(".demo-work-block")[destination].querySelector("input").focus();
        });
        move.disabled = destination < 0 || destination >= skill.effects.length;
        tools.append(move);
      }
    }
    tools.append(actionButton("×", "移除" + label, removeBlock));
    row.append(tools);
    return row;
  }

  function renderSlot(container, title, content, hint) {
    const heading = document.createElement("span");
    heading.className = "demo-slot-title";
    heading.textContent = title;
    container.replaceChildren(heading, ...content);
    if (hint) {
      const empty = document.createElement("p");
      empty.className = "demo-drop";
      empty.textContent = hint;
      container.append(empty);
    }
  }

  function renderSkill() {
    clearButton.disabled = !skill.trigger && !skill.condition && !skill.effects.length;
    const single = (key, title, hint) => {
      const block = skill[key];
      const content = block ? [blockRow(block, () => {
        skill[key] = null;
        refreshSkill("已移除「" + blocks[block.id].label + "」。");
        editor.querySelector('[data-block="' + block.id + '"]').focus();
      })] : [];
      renderSlot(slots[key], title, content, content.length ? "" : hint);
    };
    single("trigger", "触发", "放入一个触发积木");
    single("condition", "条件（可选）", "放入一个条件积木");
    const effects = skill.effects.map((block, index) => blockRow(block, () => {
      skill.effects.splice(index, 1);
      refreshSkill("已移除「" + blocks[block.id].label + "」。");
      editor.querySelector('[data-block="' + block.id + '"]').focus();
    }, index));
    renderSlot(slots.effects, "效果", effects, effects.length ? "" : "按结算顺序添加效果积木");
  }

  function addBlock(id) {
    const definition = blocks[id];
    const block = { id, amount: null };
    if (definition.slot === "effects") {
      skill.effects.push(block);
    } else {
      skill[definition.slot] = block;
    }
    refreshSkill("已放入「" + definition.label + "」。");
  }

  function testSkill() {
    if (!skill.trigger || !skill.effects.length) {
      showStatus("试跑前需要一个触发积木和至少一个效果积木。");
      return;
    }
    const numbered = [skill.condition, ...skill.effects].filter(Boolean);
    const incomplete = numbered.findIndex(block => {
      const { min, max } = blocks[block.id];
      return !Number.isInteger(block.amount) || block.amount < min || block.amount > max;
    });
    if (incomplete !== -1) {
      const { label, min, max } = blocks[numbered[incomplete].id];
      showStatus("请为「" + label + "」填写 " + min + " 到 " + max + " 的整数。");
      editor.querySelectorAll(".demo-flow input")[incomplete].focus();
      return;
    }

    const stats = { ...initial };
    const steps = ["触发「" + blocks[skill.trigger.id].label + "」。"];
    if (skill.condition && stats.opponent > skill.condition.amount) {
      steps.push("对手生命为 " + stats.opponent + "，高于 " + skill.condition.amount + "，跳过效果。");
    } else {
      if (skill.condition) steps.push("对手生命不高于 " + skill.condition.amount + "，条件成立。");
      for (const block of skill.effects) {
        switch (block.id) {
          case "damage": {
            const loss = Math.min(stats.opponent, block.amount);
            stats.opponent -= loss;
            steps.push("对手受到 " + loss + " 点伤害。");
            break;
          }
          case "heal": {
            const recovery = Math.min(30 - stats.self, block.amount);
            stats.self += recovery;
            steps.push("我方恢复 " + recovery + " 点生命。");
            break;
          }
          case "draw":
            stats.draw += block.amount;
            steps.push("我方抽 " + block.amount + " 张牌。");
            break;
        }
      }
    }
    showStatus("试跑完成。");
    showResult(stats, steps);
    if (matchMedia("(max-width: 880px)").matches && result.getBoundingClientRect().bottom > innerHeight) {
      result.scrollIntoView({ block: "start" });
    }
  }

  for (const button of editor.querySelectorAll("[data-block]")) {
    button.addEventListener("click", () => addBlock(button.dataset.block));
    button.addEventListener("dragstart", event => {
      dragging = button.dataset.block;
      event.dataTransfer.effectAllowed = "copy";
      event.dataTransfer.setData("text/plain", dragging);
      slots[blocks[dragging].slot].classList.add("demo-accepts-block");
    });
    button.addEventListener("dragend", () => {
      if (dragging) slots[blocks[dragging].slot].classList.remove("demo-accepts-block");
      dragging = null;
    });
  }

  for (const [key, slot] of Object.entries(slots)) {
    slot.addEventListener("dragover", event => {
      if (dragging && blocks[dragging].slot === key) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
      }
    });
    slot.addEventListener("drop", event => {
      if (!dragging || blocks[dragging].slot !== key) return;
      event.preventDefault();
      addBlock(dragging);
      slot.classList.remove("demo-accepts-block");
      dragging = null;
    });
  }

  editor.querySelector('[data-demo-command="example"]').addEventListener("click", () => {
    skill = {
      trigger: { id: "attack" },
      condition: { id: "threshold", amount: 22 },
      effects: [{ id: "damage", amount: 3 }, { id: "draw", amount: 1 }],
    };
    refreshSkill("示例已载入，点「试一次」看结算。");
  });
  clearButton.addEventListener("click", () => {
    skill = emptySkill();
    refreshSkill("工作区已清空。");
    editor.querySelector('[data-block="attack"]').focus();
  });
  editor.querySelector('[data-demo-command="run"]').addEventListener("click", testSkill);
  renderSkill();
  document.querySelector("[data-skill-fallback]").hidden = true;
  editor.hidden = false;
}
