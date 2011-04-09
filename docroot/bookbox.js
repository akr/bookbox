function change_thumbnail(name) {
  var i;
  var src = document[name].src;
  if (src.match(/_c\.png$/))
    document[name].src = src.replace(/_c\.png$/, '_g.png');
  else if (src.match(/_g\.png$/))
    document[name].src = src.replace(/_g\.png$/, '_m.png');
  else if (src.match(/_m\.png$/))
    document[name].src = src.replace(/_m\.png$/, '_c.png');
}
