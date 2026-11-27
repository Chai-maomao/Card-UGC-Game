const modeTabs = document.querySelector(".mode-tabs");

if (modeTabs) {
  const tabs = [...modeTabs.querySelectorAll('[role="tab"]')];
  const panels = tabs.map(tab => document.getElementById(tab.getAttribute("aria-controls")));

  if (panels.every(Boolean)) {
    function selectMode(selectedIndex) {
      tabs.forEach((tab, index) => {
        const selected = index === selectedIndex;
        tab.setAttribute("aria-selected", String(selected));
        tab.tabIndex = selected ? 0 : -1;
        panels[index].hidden = !selected;
      });
    }

    tabs.forEach((tab, index) => {
      panels[index].setAttribute("role", "tabpanel");
      panels[index].setAttribute("aria-labelledby", tab.id);
      panels[index].tabIndex = 0;
      tab.addEventListener("click", () => selectMode(index));
      tab.addEventListener("keydown", event => {
        const destinations = {
          ArrowLeft: (index - 1 + tabs.length) % tabs.length,
          ArrowRight: (index + 1) % tabs.length,
          Home: 0,
          End: tabs.length - 1,
        };
        const destination = destinations[event.key];
        if (typeof destination !== "number") return;
        event.preventDefault();
        selectMode(destination);
        tabs[destination].focus();
      });
    });

    selectMode(0);
    modeTabs.hidden = false;
  }
}
