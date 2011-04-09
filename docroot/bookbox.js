function change_thumbnail(stem) {
  name = "img" + stem;
  var src = document[name].src;
  if (src.match(/_c\.png$/))
    document[name].src = src.replace(/_c\.png$/, '_g.png');
  else if (src.match(/_g\.png$/))
    document[name].src = src.replace(/_g\.png$/, '_m.png');
  else if (src.match(/_m\.png$/))
    document[name].src = src.replace(/_m\.png$/, '_c.png');
}

function thumbnail_all_color(stems, ch) {
  var suffix = '_' + ch + '.png';
  for (var i in stems) {
    name = "img" + stems[i];
    document[name].src = document[name].src.replace(/_[cgm]\.png$/, suffix);
  }
}
