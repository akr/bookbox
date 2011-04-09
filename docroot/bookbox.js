function change_thumbnail(stem) {
  var name = "img" + stem;
  var src = document[name].src;
  if (src.match(/_c\.png$/))
    set_image_color_mode(stem, 'g');
  else if (src.match(/_g\.png$/))
    set_image_color_mode(stem, 'm');
  else if (src.match(/_m\.png$/)) {
    set_image_color_mode(stem, 'n');
  }
}

function thumbnail_all_color(stems, mode) {
  for (var i in stems) {
    set_image_color_mode(stems[i], mode);
  }
}

function set_image_color_mode(stem, mode) {
  if (document.getElementById("pages:out"+stem+".pnm:colormode").value == mode)
    return;
  var img = document["img"+stem];
  var suffix = '_' + (mode == 'n' ? 'c' : mode) + '.png';
  img.src = img.src.replace(/_[cgm]\.png$/, suffix);
  document.getElementById("pages:out"+stem+".pnm:colormode").value = mode;
  var fullsize = document.getElementById("fullsize"+stem);
  fullsize.href = fullsize.href.replace(/_[cgm]\.png$/, suffix);
  if (mode == 'n') {
    var a = document.createElement('a');
    a.href = 'javascript:set_image_color_mode("'+stem+'", "c")';
    a.insertBefore(document.createTextNode('show'), null);
    img.style.display = 'none';
    img.parentNode.insertBefore(a,img)
  }
  else {
    var a = img.previousSibling;
    while (a && a.nodeName == '#text') { a = a.previousSibling; }
    if (a && a.nodeName == 'A' && a.firstChild.nodeName == '#text' && a.firstChild.data == 'show') {
      img.parentNode.removeChild(a);
    }
    img.style.display = 'inline';
  }
}

function flip_lr() {
  var rows = document.getElementById("pages").rows;
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var cells = row.cells;
    var n = cells.length;
    for (var j = cells.length-2; 0 <= j; j--) {
      row.insertBefore(cells.item(j), null)
    }
  }
  var input = document.getElementById("ViewerPreferencesDirection");
  if (input.value == "L2R")
    input.value = "R2L";
  else
    input.value = "L2R";
}
