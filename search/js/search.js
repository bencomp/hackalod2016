#!/usr/bin/perl

use strict;
use CGI qw(:standard :cgi-lib);

print header(-type=>"application/javascript",-charset=>'utf-8',-expires=>'1s');

print <<'EOJS';
$(document).ready(function() {
  var annotationServer = 'http://172.16.14.64:8889/annotation/';
  var imgServer;
  var imgServerPost;
  if (1) {
    imgServer = 'http://imageviewer.kb.nl/ImagingService/imagingService?h=150&id=';
    imgServerPost = '';
  }
  else {
    imgServer = 'http://imageserver:8182/iiif/2/';
    imgServerPost = '/full/!150,150/0/default.jpg';
  }
  $('.book .pages').each(function(e) {
    var pagesdiv = $(this);
    var bookid = pagesdiv.data('bookid');
    var pagesurl = 'bookimages?bookid=' + bookid;
    $.getJSON(pagesurl, function( data ) {
      if (data['pages']) {
        $.each(data['pages'], function(i, page) {
          var pagehtml = '<DIV data-pageid="'+page['id']+'" class="page">'
                       + '<IMG src="'+imgServer+page['id']+imgServerPost+'">'
                       + '<DIV class="caption">' + page['title'] + '</DIV>'
                       + '</DIV>';
          pagesdiv.append(pagehtml);
        });
	pagesdiv.find('.page').click(function() {
	  if ($(this).hasClass('selected')) {
	    $(this).removeClass('selected');
            setSelection($(this).data('pageid'), '0');
	  }
	  else {
	    $(this).addClass('selected');
            setSelection($(this).data('pageid'), '1');
	  }
	});
	pagesdiv.find('.page').each(function() {
          if (getSelection($(this).data('pageid')) === '1') {
            $(this).addClass('selected');
          }
        });
      }
    });
  });

  $('#lefttoright').change(function(e) {
    e.preventDefault();
    if (this.checked) {
      $('.pages').addClass('lefttoright');
    }
    else {
      $('.pages').removeClass('lefttoright');
    }
  });

  $('#show').change(function(e) {
    e.preventDefault();
    var value = $(this).val();
      if (value == 'showall') {
        $('#searchresult .page').show();
      }
      else if (value == 'showsel') {
        $('#searchresult .page.selected').show();
        $('#searchresult .page').not('.selected').hide();
      }
      else if (value == 'showunsel') {
        $('#searchresult .page.selected').hide();
        $('#searchresult .page').not('.selected').show();
      }
  });

  $('#viewselection').click(function(e) {
    e.preventDefault();
    var q = $('#query').val();
    var s = '';
    $('#searchresult .page.selected').each(function(i) {
      var pageid = $(this).data('pageid');
      if (s) {
        s += ',';
      }
      s += pageid;
    });
    document.location = 'http://imageserver/viewer.html?q='+q+'&s='+s; 
  });
});
  
  // Annotations
{
    var annotations;

  function getAnnotations(completion) {
    if (annotations != undef) {
      if (completion) {
        completion(annotations);
      }
    }
    $.getJSON(annotationServer, function(data) {
      if (data['resources']) {
        $.each(data['resources'], function(i, resource) {

        }); 
      }
    });
  }

  // Storing selections
  function setSelection(key,value) {
    if (typeof(Storage) !== "undefined") {
      localStorage.setItem(key, value);
    }
  }
  function getSelection(key) {
    if (typeof(Storage) !== "undefined") {
      return localStorage.getItem(key);
    }
    return undef;
  }
}  

EOJS
