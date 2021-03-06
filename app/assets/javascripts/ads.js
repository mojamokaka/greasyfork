window.addEventListener("codefund", function(evt) {
  if (evt.detail.status !== 'ok' || evt.detail.house) {
    var carbonPlaceholder = document.getElementById("_carbonads_js");
    if (!carbonPlaceholder) {
      return;
    }
    var carbonScript = document.createElement('script');
    carbonScript.type= 'text/javascript';
    carbonScript.src= carbonPlaceholder.getAttribute("data-src");
    carbonScript.setAttribute("id", carbonPlaceholder.getAttribute("id"));

    var parent = carbonPlaceholder.parentNode;
    parent.removeChild(carbonPlaceholder);
    parent.appendChild(carbonScript);
    parent.style.display = "block";

    var codefundElement = document.getElementById("codefund");
    codefundElement.parentNode.removeChild(codefundElement);
  }
});