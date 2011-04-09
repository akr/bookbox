function change_thumbnail(stem) {
  var name = "img" + stem;
  var src = document[name].src;
  if (src.match(/_c\.png$/))
    set_thumbnail_color_mode(stem, 'g');
  else if (src.match(/_g\.png$/))
    set_thumbnail_color_mode(stem, 'm');
  else if (src.match(/_m\.png$/))
    set_thumbnail_color_mode(stem, 'c');
}

function thumbnail_all_color(stems, mode) {
  for (var i in stems) {
    set_thumbnail_color_mode(stems[i], mode);
  }
}

function set_thumbnail_color_mode(stem, mode) {
  var name = "img" + stem;
  var suffix = '_' + mode + '.png';
  document[name].src = document[name].src.replace(/_[cgm]\.png$/, suffix);
}
