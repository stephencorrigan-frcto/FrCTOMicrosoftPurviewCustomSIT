$(document).ready(function () {
  $("#refresh").on("click", function () {
    $.getJSON("/api/prices", function (data) { render(data); });
  });
});