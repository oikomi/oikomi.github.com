function $(s){return document.getElementById(s)?document.getElementById(s):s;}
function keypress(e)
{
    var keyCode = 0;
    var e = e || window.event;
    keyCode = e.keyCode || e.which || e.charCode;
    switch(keyCode){
    case 84:case 116: goTop();break; // t T
    case 98:case 66:  document.location="/book.html";break; // b B 
    case 78:case 110: document.location="/note.html";break; // N n
    case 97:case 65:  document.location="/about.html";break; // a A
    case 80:case 112: document.location="/allposts.html";break; // p P
    case 72:case 104: document.location="/";break; // h H
    default:break;
    }
}

function goTop(acceleration, time) {
    acceleration = acceleration || 0.1;
    time = time || 16;
    
    var x1 = 0;
    var y1 = 0;
    var x2 = 0;
    var y2 = 0;
    var x3 = 0;
    var y3 = 0;
    
    if (document.documentElement) {
	x1 = document.documentElement.scrollLeft || 0;
	y1 = document.documentElement.scrollTop || 0;
    }
    if (document.body) {
	x2 = document.body.scrollLeft || 0;
	y2 = document.body.scrollTop || 0;
    }
    var x3 = window.scrollX || 0;
    var y3 = window.scrollY || 0;

    var x = Math.max(x1, Math.max(x2, x3));
    var y = Math.max(y1, Math.max(y2, y3));

    var speed = 1 + acceleration;
    window.scrollTo(Math.floor(x / speed), Math.floor(y / speed));
    
    if(x > 0 || y > 0) {
	var invokeFunction = "goTop(" + acceleration + ", " + time + ")";
	window.setTimeout(invokeFunction, time);
    }
}
