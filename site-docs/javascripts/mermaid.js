mermaid.initialize({ startOnLoad: false });

let renderPromise = Promise.resolve();

document$.subscribe(function () {
  renderPromise = renderPromise.then(function () {
    document.querySelectorAll("pre.mermaid:not([data-processed])").forEach(function (block) {
      const diagram = document.createElement("div");
      diagram.className = block.className;
      diagram.textContent = block.textContent;
      block.replaceWith(diagram);
    });

    return mermaid.run({
      nodes: document.querySelectorAll(".mermaid:not([data-processed])"),
    });
  });
});
