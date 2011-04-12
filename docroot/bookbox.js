function check_all(stems, checked_value) {
  for (var page = 0; page < stems.length; page++) {
    var input = document.getElementById("checkbox"+page);
    input.checked = checked_value;
  }
}

function check_seq(stems) {
  var min, max;
  for (var page = 0; page < stems.length; page++) {
    var input = document.getElementById("checkbox"+page);
    if (input.checked) {
      if (min == undefined)
        min = page;
      max = page;
    }
  }
  if (min != undefined) {
    for (var page = min; page <= max; page++) {
      var input = document.getElementById("checkbox"+page);
      input.checked = 'checked';
    }
  }
}

function checked_set_image_color_mode(stems, mode) {
  checked = [];
  for (var page = 0; page < stems.length; page++) {
    if (document.getElementById("checkbox"+page).checked)
      checked.push(page);
  }
  for (var i = 0; i < checked.length; i++) {
    set_image_color_mode(stems, checked[i], mode);
  }
}

function cycle_color_mode(stems, page) {
  var stem = stems[page];
  var mode = document.getElementById("pages:out"+stem+".pnm:colormode").value;
  if (mode == 'c')
    set_image_color_mode(stems, page, 'g');
  else if (mode == 'g')
    set_image_color_mode(stems, page, 'm');
  else if (mode == 'm')
    set_image_color_mode(stems, page, 'n');
  else if (mode == 'n')
    set_image_color_mode(stems, page, 'c');
}

function set_image_color_mode(stems, page, mode) {
  var stem = stems[page];
  if (document.getElementById("pages:out"+stem+".pnm:colormode").value == mode)
    return;
  document.getElementById("pages:out"+stem+".pnm:colormode").value = mode;

  var full = document.getElementById("full"+page);
  var img = document.getElementById("img"+page);
  var a = document.getElementById("show"+page);
  var ball = document.getElementById("ball"+page);

  var suffix = '_' + (mode == 'n' ? 'c' : mode) + '.png';
  img.src = img.src.replace(/_[cgm]\.png$/, suffix);
  full.href = full.href.replace(/_[cgm]\.png$/, suffix);

  ball.src = ball.src.replace(/_[cgmn]\.png$/,  '_' + mode + '.png');

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

function image_sort(stems, uri, sign, sortkey, set_stems) {
  var stats;
  var http_request = new XMLHttpRequest();
  http_request.open( "GET", uri, true );
  http_request.onreadystatechange = function () {
      if ( http_request.readyState == 4 ) {
          if ( http_request.status == 200 ) {
              stats = eval( "(" + http_request.responseText + ")" );
              image_sort_sub(stems, stats, sign, sortkey, set_stems);
          } else {
              alert( "There was a problem with the URL." );
          }
          http_request = null;
      }
  };
  http_request.send(null);
}

function image_sort_sub(stems, stats, sign, sortkey, set_stems) {
  var ary = stems.slice();
  ary.sort(function (stem1, stem2) {
      return sign * (stats["small"+stem1+"_c.pnm"][sortkey] -
                     stats["small"+stem2+"_c.pnm"][sortkey]);
  });
  update_stems(ary, set_stems);
}

function update_stems(new_stems, set_stems) {
  for (var page = 0; page < new_stems.length; page++) {
    var stem = new_stems[page];
    var mode = document.getElementById("pages:out"+stem+".pnm:colormode").value;

    var full = document.getElementById("full"+page);
    var checkbox = document.getElementById("checkbox"+page);
    var img = document.getElementById("img"+page);
    var a = document.getElementById("show"+page);

    var suffix = '_' + (mode == 'n' ? 'c' : mode) + '.png';
    img.src = img.src.replace(/[^\/]+_[cgm]\.png$/, "small"+stem+suffix);
    full.href = full.href.replace(/[^\/]+_[cgm]\.png$/, "fullsize"+stem+suffix);
    checkbox.name = "checkbox"+stem;
    checkbox.checked = undefined;

    if (mode == 'n') {
      a.style.display = 'inline'
      img.style.display = 'none';
    }
    else {
      a.style.display = 'none'
      img.style.display = 'inline';
    }
  }
  set_stems(new_stems);
}
