function change_thumbnail(stem) {
  var name = "img" + stem;
  var src = document[name].src;
  if (src.match(/_c\.png$/))
    set_image_color_mode(stem, 'g');
  else if (src.match(/_g\.png$/))
    set_image_color_mode(stem, 'm');
  else if (src.match(/_m\.png$/))
    set_image_color_mode(stem, 'c');
}

function thumbnail_all_color(stems, mode) {
  for (var i in stems) {
    set_image_color_mode(stems[i], mode);
  }
}

function set_image_color_mode(stem, mode) {
  var o;
  o = document["img"+stem];
  o.src = o.src.replace(/_[cgm]\.png$/, '_' + mode + '.png');
  document.getElementById("colormode"+stem).value = mode;
  o = document.getElementById("fullsize"+stem);
  o.href = o.href.replace(/_[cgm]\.png$/, '_' + mode + '.png');
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
}
