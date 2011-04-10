function change_thumbnail(stem) {
  var mode = document.getElementById("pages:out"+stem+".pnm:colormode").value;
  if (mode == 'c')
    set_image_color_mode(stem, 'g');
  else if (mode == 'g')
    set_image_color_mode(stem, 'm');
  else if (mode == 'm')
    set_image_color_mode(stem, 'n');
  else if (mode == 'n')
    set_image_color_mode(stem, 'c');
}

function thumbnail_all_color(stems, mode) {
  for (var i in stems) {
    set_image_color_mode(stems[i], mode);
  }
}

function set_image_color_mode(stem, mode) {
  if (document.getElementById("pages:out"+stem+".pnm:colormode").value == mode)
    return;
  document.getElementById("pages:out"+stem+".pnm:colormode").value = mode;

  var suffix = '_' + (mode == 'n' ? 'c' : mode) + '.png';
  var img = document["img"+stem];
  img.src = img.src.replace(/_[cgm]\.png$/, suffix);
  var fullsize = document.getElementById("fullsize"+stem);
  fullsize.href = fullsize.href.replace(/_[cgm]\.png$/, suffix);

  var a = document.getElementById("show"+stem);
  if (mode == 'n') {
    a.style.display = 'inline'
    img.style.display = 'none';
  }
  else {
    a.style.display = 'none'
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
