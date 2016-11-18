package XMLHash;
require Exporter;
use base 'Exporter';
@EXPORT_OK = qw/parsexmlfile parsexmlstring mergexml array_for_path hash_for_path string_for_path text_for_path data_for_path textarray_for_path type_for_path defined_path add_to_path xml_doc_string xml_string checkxmlsyntax deep_copy/; 
use Encode;

# XMLHash is a package for reading, writing and querying XML
# structures.

# THIS PACKAGE NEED TO BE MADE OO (overload, tie?)

# prototypes:
sub parsexmlfile($;$);
sub parsexmlstring($;$);
sub mergexml($$;$);
sub array_for_path($$);
sub hash_for_path($$);
sub string_for_path($$);
sub text_for_path($$);
sub data_for_path($$);
sub textarray_for_path($$);
sub type_for_path($$);
sub defined_path($$);
sub add_to_path($$;$);
sub xml_doc_string($);
sub xml_string($;$);
sub checkxmlsyntax($$;$);
sub deep_copy($);

our $VERSION = '0.8';

use constant {
      INDENT_STR => '  ',
      PARSE_START_XML_FILE => 0,
      PARSE_INSIDE_XML_HEADER => 1,
      PARSE_INSIDE_XML => 2,
      PARSE_INSIDE_CDATA => 3,
      PARSE_INSIDE_COMMENT => 4,
      PARSE_INSIDE_PI => 5, 
      PARSE_BEFORE_ATTR => 6,
      PARSE_AFTER_ATTR_NAME => 7,
      PARSE_BEFORE_ATTR_VALUE => 8,
    };
$XMLHash::RE_NAME = qr{(?i:(?:[a-z_]+:)?[a-z_]+[a-z0-9._:-]*)};
$XMLHash::RE = {
      SPACE_AT_START_LINE => qr{^\s*},
      SPACE_AT_END_LINE => qr{\G\s*\z},
      BEFORE_START_OF_XML_HEADER => qr{\G<\?xml\s*},
      BEFORE_END_OF_XML_HEADER => qr{\G\s*\?>}, 
      BEFORE_START_OF_TAG => qr{\G<(\@?$XMLHash::RE_NAME)\s*},
      BEFORE_ATTR_NAME => qr{\G(?<!\w)($XMLHash::RE_NAME)},
      AFTER_ATTR_NAME => qr{\G\s*=\s*},
      BEFORE_ATTR_VALUE => qr{\G(?:\"([^\"]*)\"\s*|\'([^\']*)\'\s*)},
      BEFORE_END_OF_TAG => qr{\G\s*>},
      BEFORE_END_OF_EMPTY_TAG => qr{\G\s*/>},
      BEFORE_START_OF_END_TAG => qr{\G</(\@?$XMLHash::RE_NAME)>},
      BEFORE_START_OF_COMMENT => qr{\G<!--},
      BEFORE_START_OF_PI => qr{\G<\?(?!xml)},
      BEFORE_START_OF_CDATA => qr{\G<!\[CDATA\[},
      BEFORE_END_OF_CDATA => qr{\G(.*?)\]\]>},
      BEFORE_END_OF_PI => qr{\G.*?\?>},
      BEFORE_END_OF_COMMENT => qr{\G.*?-->},
      EAT_TO_END_OF_LINE => qr{\G(.*)$},
      TEXT => qr{\G([^<]+)},
};

{
  my %openfiles;
  my $linecounter = 0;
  my @stringlines;

  sub _set_filehandle {
    my $fname = shift;
    die "File $fname is already open, cannot recursively include files.\n"
      if exists $openfiles{$fname};
    $openfiles{$fname}{linecounter} = 0;
    $openfiles{$fname}{fh} = shift;
  }
  sub _next_file_line {
    my $fname = shift;
    my $fh = $openfiles{$fname}{fh};
    $openfiles{$fname}{linecounter}++;
    <$fh>;
  }
  sub _delete_filehandle {
    my $fname = shift;
    delete $openfiles{$fname};
  }
  sub _set_stringdata {
    $linecounter = 0;
    @stringlines = split(/^/, shift);
  }
  sub _next_string_line {
    $stringlines[$linecounter++];
  }
}

sub parsexmlfile($;$) {
  my $filename = shift;
  my $partxml = shift;
  my $fh;

  die "\r$filename is not a readable xml file\n" unless (-f $filename && -s _);
  open $fh, $filename or die "Cannot open xml file $filename\n";
  
  _set_filehandle($filename, $fh); 

  my $result = _parse_it(\&_next_file_line, $partxml, $filename);

  _delete_filehandle($filename);

  return $result;
}

sub parsexmlstring($;$) {
  my $data = shift;
  my $partxml = shift;

  _set_stringdata($data);

  return _parse_it(\&_next_string_line, $partxml);
}

sub _parse_it(&) {
# read an XML file and make a hash of it's content. See MUCdoc for more info.
  my $funcnext = shift;
  my $partxml = shift || 0;
  my $inputkey = shift;
  my $m = 0;
  my $line;
  my $hash = {};
  my $pointer;
  my $element;
  my $old_pos = 0;
  my @el_path;
  my @p_path;
  my %blocks;
  my $order = 0;
  my $start_line = 0;
  my $old_m;
  my $encoding;

  eval {
    push @p_path, $hash;
    while ($line = $funcnext->($inputkey)) {
      $line =~ m/$XMLHash::RE->{SPACE_AT_START_LINE}/gci;
      while(not $line =~ m/$XMLHash::RE->{SPACE_AT_END_LINE}/gci) {
        $start_line = $. unless $m == $old_m;
        $old_m = $m;
        $old_pos = pos($line);
        if ($m == PARSE_START_XML_FILE) {
          if ($line =~ m/$XMLHash::RE->{BEFORE_START_OF_XML_HEADER}/gci) {
            $m = PARSE_INSIDE_XML_HEADER;
          } 
        }
        elsif ($m == PARSE_INSIDE_XML_HEADER) {
          if ($line =~ m/$XMLHash::RE->{BEFORE_ATTR_NAME}/gci) {
            my $attr_name = $1;
            if ($line =~ m/$XMLHash::RE->{AFTER_ATTR_NAME}/gci && $line =~ m/$XMLHash::RE->{BEFORE_ATTR_VALUE}/gci) {
              $hash->{'@'.$attr_name} = $+;
            }
            else {
              die "Expecting something like: $attr_name=\"[value]\", ".
                  "but found something else.\n";
            }
            die "Attribute '$attr_name' already exists.\n"
              if exists $pointer->{$attr_name};
          }
          if ($line =~ m/$XMLHash::RE->{BEFORE_END_OF_XML_HEADER}/gci) {
            $m = PARSE_INSIDE_XML; 
            if(exists $hash->{'@version'}) {
              $hash->{'_xml_version_'} = $hash->{'@version'};
              delete $hash->{'@version'};
            }
            else {
              die "Xml header must include a version attribute\n";
            }
            if(exists $hash->{'@encoding'}) {
              $encoding = $hash->{'@encoding'};
              $hash->{'_xml_encoding_'} = $encoding;
              delete $hash->{'@encoding'};
            }
            if(exists $hash->{'@standalone'}) {
              $hash->{'_xml_standalone_'} = $hash->{'@standalone'};
              delete $hash->{'@standalone'};
            }
            die "Xml header may only contain version, encoding or ".
                "standalone attributes\n"
              if grep {m'^@'} keys %{$hash};
          }
        }
        elsif ($m == PARSE_INSIDE_XML) {
          if ($line =~ m/$XMLHash::RE->{BEFORE_START_OF_TAG}/gci) {
            $pointer = $p_path[$#p_path];
            my $el_name = $1;
            if ($pointer == $hash && not @el_path) {
              die "Only one root element allowed.\n" 
                if !$partxml && grep {!m'^_.*_$'} keys %{$hash};
            }
            if (exists $pointer->{$el_name}) {
              die "Attribute $el_name already exists.\n"
                if $el_name =~ m'^@' && exists $pointer->{$el_name};
              push @{$pointer->{$el_name}}, {'_order_'=>$order++};
            }
            else {
              $pointer->{$el_name} = [{'_order_'=>$order++}];
            }
            push @p_path, $pointer->{$el_name}->[$#{$pointer->{$el_name}}];
            push @el_path, $el_name;
            $m = PARSE_BEFORE_ATTR;
          }
          elsif ($line =~ m/$XMLHash::RE->{BEFORE_START_OF_END_TAG}/gci) {
            $element = pop @el_path;
            $pointer = pop @p_path;
            if ($element ne $1) {
              die "Expecting closing element '$element' but found '$1'\n";
            }
            if ($element =~ /^x(?:ml|include):include$/) {
              _include_xml($element, $pointer, \@p_path);
            }
            if (!exists $pointer->{'#all'} &&
                (grep {!/^[_#\@]/} keys %{$pointer}) == 0) {
              $pointer->{'#all'}->[0]->{'#text'} = '';
            }
            $m = PARSE_INSIDE_XML;
          }
          elsif ($line =~ m/$XMLHash::RE->{BEFORE_START_OF_COMMENT}/gci) {
            $m = PARSE_INSIDE_COMMENT;
          }
          elsif ($line =~ m/$XMLHash::RE->{BEFORE_START_OF_PI}/gci) {
            $m = PARSE_INSIDE_PI;
          }
          elsif ($line =~ m/$XMLHash::RE->{BEFORE_START_OF_CDATA}/gci) {
            $m = PARSE_INSIDE_CDATA;
          }
          elsif ($line =~ m/$XMLHash::RE->{TEXT}/gci) {
            $element = $el_path[$#el_path];
            $pointer = $p_path[$#p_path];
            my $value = $1;
            if ($element =~ m'^@') {
              $p_path[$#p_path - 1]->{$element} = _char_decode($value, $encoding);  
            }
            else {
              $pointer->{'#all'} = [] unless exists $pointer->{'#all'};
              push @{$pointer->{'#all'}}, {'_order_'=>$order++,
                                           '#text'=>_char_decode($value, $encoding)};
            }
          }
        }
        elsif ($m == PARSE_BEFORE_ATTR) {
          if ($line =~ m/$XMLHash::RE->{BEFORE_ATTR_NAME}/gci) {
            my $attr_name = '@'.$1;
            $m = PARSE_AFTER_ATTR_NAME;
            $pointer = $p_path[$#p_path];
            $pointer->{$attr_name} = '';
            push @p_path, \$pointer->{$attr_name};
            push @el_path, $attr_name;
          }
          elsif ($line =~ m/$XMLHash::RE->{BEFORE_END_OF_TAG}/gci) {
            $m = PARSE_INSIDE_XML;
          }
          elsif ($line =~ m/$XMLHash::RE->{BEFORE_END_OF_EMPTY_TAG}/gci) {
            pop @p_path;
            my $el_name = pop @el_path;
            if ($el_name =~ /^x(?:ml|include):include$/) {
              _include_xml($el_name, $pointer, \@p_path);
            }
            $m = PARSE_INSIDE_XML;
          }
        }
        elsif ($m == PARSE_AFTER_ATTR_NAME) {
          if ($line =~ m/$XMLHash::RE->{AFTER_ATTR_NAME}/gci) {
            $m = PARSE_BEFORE_ATTR_VALUE;
          }
        }
        elsif ($m == PARSE_BEFORE_ATTR_VALUE) {
          if ($line =~ m/$XMLHash::RE->{BEFORE_ATTR_VALUE}/gci) {
            $m = PARSE_BEFORE_ATTR;
            my $attr_name = pop @el_path;
            my $pv = pop @p_path;
            if ($attr_name eq '@block_id') {
              my $block_id = $+;
              if (exists $blocks{$block_id}) {
                foreach my $k (keys %{$blocks{$block_id}}) {
                  $p_path[$#p_path]->{$k} = deep_copy($blocks{$block_id}->{$k})
                    unless exists $p_path[$#p_path]->{$k};
                }
              }
              else {
                $blocks{$block_id} = $p_path[$#p_path];
              }
              delete $p_path[$#p_path]->{$attr_name};
            }
            elsif ($attr_name eq '@regexpxx') {
              ${$pv} = qr"$+";
            }
            else { 
              ${$pv} = _char_decode($+, $encoding);
            }
          }
        }
        elsif ($m == PARSE_INSIDE_CDATA) {
          my $text;
          if ($line =~ m/$XMLHash::RE->{BEFORE_END_OF_CDATA}/gci) {
            $text = $1;
            $m = PARSE_INSIDE_XML;
          }
          else {
            ($text) = $line =~ m/$XMLHash::RE->{EAT_TO_END_OF_LINE}/gci;
            $text .= "\n";
          }
          $pointer = $p_path[$#p_path];
          $pointer->{'#all'} = [] unless exists $pointer->{'#all'};
          push @{$pointer->{'#all'}}, {'_order_'=>$order++, '#cdata'=>$text};
        }
        elsif ($m == PARSE_INSIDE_PI) {
          if ($line =~ m/$XMLHash::RE->{BEFORE_END_OF_PI}/gci) {
            $m = PARSE_INSIDE_XML;
          } 
          else {
            $line =~ m/$XMLHash::RE->{EAT_TO_END_OF_LINE}/gci;
          }
        }
        elsif ($m == PARSE_INSIDE_COMMENT) {
          if ($line =~ m/$XMLHash::RE->{BEFORE_END_OF_COMMENT}/gci) {
            $m = PARSE_INSIDE_XML;
          } 
          else {
            $line =~ m/$XMLHash::RE->{EAT_TO_END_OF_LINE}/gci;
          }
        }
        $m = PARSE_INSIDE_XML, next if $m == PARSE_START_XML_FILE;
        die "Unexpected character on line $. at:\n$line".(' 'x$old_pos)."^\n"
          if $old_pos == pos($line);
      }
    } 
  };
  die "Syntax error on line $., position $old_pos:\n$@" if ($@);
  unless ($m == PARSE_INSIDE_XML) {
    my $error = "Unknown error";
    $error = "Xml header not closed properly" 
      if $m == PARSE_INSIDE_XML_HEADER;
    $error = "CDATA section not closed properly" 
      if $m == PARSE_INSIDE_CDATA;
    $error = "Comment not closed properly" 
      if $m == PARSE_INSIDE_COMMENT;
    $error = "Processing Instruction section not closed properly"
      if $m == PARSE_INSIDE_PI;
    die "$error, starting at line $start_line.\n";
  }
  die "Missing closing tag for element '$el_path[$#el_path]'.\n" if @el_path;

  return $hash;
}

sub _include_xml {
  my $incelname = shift;
  my $inchash = shift;
  my $p_path = shift;
  my %include = %{$inchash};
 
  my $href = delete $include{'@href'};
 
  foreach my $el (keys %include) {
    next if $el =~ /^_/;
    die "$incelname cannot contain other elements, like $el.\n";
  } 
  my $incxml = parsexmlfile($href, 1); 
  my $parent = $p_path->[$#{$p_path}];

  my $index = $parent->{$incelname}[0]{'_order_'};
  delete $parent->{$incelname}; 
  foreach my $el (keys %{$incxml}) {
    next if $el =~ /^_/;
    if ($el =~ /^\@/) {
      # overwrite the same attributes of the parent element
      $parent->{$el} = $incxml->{$el};
      next;
    }
    foreach $item (@{$incxml->{$el}}) {
      $item->{'_order_'} += $index;
    }
    if (exists $parent->{$el}) {
      # the format of XMLHash dictates that both are ARRAYs...
      push @{$parent->{$el}}, @{$incxml->{$el}};
    }
    else {
      $parent->{$el} = $incxml->{$el};
    }
  }
  $parent;
}

sub _char_encode {
  my $value = shift;
  my $encoding = shift;

  $value =~ s/&(?!\w+;)(?!#\d+;)/&amp;/g;
  $value =~ s/</&lt;/g;
  $value =~ s/>/&gt;/g;
  $value =~ s/'/&apos;/g;
  $value =~ s/"/&quot;/g;

  $value = encode($encoding, $value) if defined $encoding;

  return $value;
}

sub _char_decode {
  my $value = shift;
  my $encoding = shift;

  $value =~ s/&#x([0-9a-f]+);/"chr(0x$1)"/giee;
  $value =~ s/&amp;/&/g;
  $value =~ s/&lt;/</g;
  $value =~ s/&gt;/>/g;
  $value =~ s/&apos;/'/g;
  $value =~ s/&quot;/"/g;

  $value = decode($encoding, $value) if defined $encoding;

  return $value;
}

sub mergexml($$;$) {
  my ($h1,$h2,$mode) = @_;
  
  if ($mode eq 'data') {
    return _mergedataxml($h1,$h2);
  }
  else {
    return _mergexml($h1,$h2);
  }
}

sub _mergexml($$) {
  my $hash1 = shift;
  my $hash2 = shift;

  foreach my $k2 (keys %{$hash2}) {
    if (exists $hash1->{$k2}) {
      if (ref $hash1->{$k2} eq 'ARRAY') {
        if (ref $hash2->{$k2} eq 'ARRAY') {
          push @{$hash1->{$k2}}, @{$hash2->{$k2}};
        }
        else {
          push @{$hash1->{$k2}}, $hash2->{$k2};
        }
      }
      else {
        $hash1->{$k2} = $hash2->{$k2};
      }
    }
    else {
      $hash1->{$k2} = $hash2->{$k2}
        unless $k2 eq '_order_' && exists $hash1->{$k2}; 
    }
  }
  return $hash1;
}

sub _mergedataxml($$) {
  my $hash1 = shift;
  my $hash2 = shift;

  if (ref $hash1 eq 'ARRAY') {
    foreach my $ih1 (@{$hash1}) {
      _mergedataxml($ih1,$hash2);
    }
  }
  elsif (ref $hash2 eq 'ARRAY') {
    foreach my $ih2 (@{$hash2}) {
      _mergedataxml($hash1,$ih2);
    }
  }
  elsif (ref $hash2 eq 'HASH') {
    foreach my $k2 (keys %{$hash2}) {
      next if $k2 eq '_order_';
      if (exists $hash1->{$k2}) {
        if (ref $hash1->{$k2} eq '' && ref $hash2->{$k2} eq '') {
          $hash1->{$k2} = $hash2->{$k2} 
            unless length($hash1->{$k2}) > 0;
        }
        else {
          _mergedataxml($hash1->{$k2}, $hash2->{$k2});
        }
      }
      else {
        $hash1->{$k2} = $hash2->{$k2};
      }
    }
  }
  else {
    die "MUC::XMLHash: _mergedataxml: incompatible ".(ref $hash1)." != ".(ref $hash2);
  }
  return $hash1;
}

sub array_for_path($$) {
  my $hash = shift;
  my $path = shift;
  my $result = _subhash($hash, $path);

  return undef unless defined $result;
  die "array_for_path: path '$path' doesn't result in array"
    unless ref $result eq 'ARRAY';

  return $result;
}

sub hash_for_path($$) {
  my $hash = shift;
  my $path = shift;
  my $result = _subhash($hash, $path);

  return undef unless defined $result;
  if (ref $result eq 'ARRAY') {
    if (@{$result} == 1) {
      $result = $result->[0];
    }
    else {
      return {};
      die "hash_for_path: path '$path' not specific enough";
    }
  }
  die "hash_for_path: path '$path' doesn't result in hash"
    unless ref $result eq 'HASH';

  return $result;
}  

sub string_for_path($$) {
  my $hash = shift;
  my $path = shift;
  my $result = _subhash($hash, $path);

  die "string_for_path: path '$path' doesn't result in string"
    unless ref $result eq '';

  return $result;
}

sub text_for_path($$) {
  my $hash = shift;
  my $path = shift;
  my $result;

  if ($path) {
    $result = _subhash($hash, $path);
  }
  else {
    $result = $hash;
  }
  if (ref $result eq 'ARRAY') {
    if (@{$result} == 1) {
      $result = $result->[0];
    }
    else {
      die "text_for_path: path '$path' not specific enough:\n"
         .xml_string($hash);
    }
  }
  return $result if ref $result eq '';
  die "text_for_path: '$path' doesn't result in text:\n@{[%$result]}"
    unless (exists $result->{'#all'});
  my $results = [];
  _ntext($result->{'#all'}, $results);
  return $results->[0] if (@{$results} == 1);

  local $" = '';
  return "@{$results}"; 
}

sub data_for_path($$) {
  my $hash = shift;
  my $path = shift;
  my $result;

  if ($path) {
    $result = _subhash($hash, $path);
  }
  else {
    $result = $hash;
  }
  if (ref $result eq 'ARRAY') {
    if (@{$result} == 1) {
      $result = $result->[0];
    }
    else {
      die "text_for_path: path '$path' not specific enough";
    }
  }
  return $result if ref $result eq '';

  die "data_for_path: '$path' doesn't result in data"
    unless (exists $result->{'#all'});
  return _xml_string($result, undef, '', 0, 1);
}

sub textarray_for_path($$) {
  my $hash = shift;
  my $path = shift;
  my $result = _subhash($hash, $path);
  my @ra;

  return undef unless defined $result;
  if (@{$result} == 1) {
    my $t = text_for_path($result->[0], '');
    return ($t) if defined $t;
  }
  else {
    foreach my $item (@{$result}) {
      my $t = text_for_path($item, '');
      push @ra, $t if defined $t; 
    }
    return @ra;
  }
  return undef;
}

sub type_for_path($$) {
  my $hash = shift;
  my $path = shift;
  my $result = _subhash($hash, $path);

  return ref $result;
}

sub defined_path($$) {
  my $hash = shift;
  my $path = shift;
  my $result = _subhash($hash, $path);

  return defined $result;
}

sub _subhash($$) {
  my $hash = shift;
  my $path = shift;
  my $sh = $hash;
  my $osh;
 
  if ($path =~ m{^count\((.*)\)$}) {
    my $result = _subhash($hash, $1);

    return undef unless defined $result;
    die "array_for_path: path '$1' doesn't result in array and thus cannot be counted"
      unless ref $result eq 'ARRAY';

    return scalar @{$result};
  }
  if ($path !~ m{[/\[]}) {
    return $sh->{$path} if exists $sh->{$path};
    return undef;
  }

  my @segs = split m{(?<!/)/(?!/)}, $path;
  my $c = 0;
  foreach my $n (@segs) {
    $c++;
    if (ref $sh eq 'HASH') {
      if ($n =~ /^([^\[]+)(\[(-?\d+|\+)\])?$/) {
        my $name = $1;
        my $nr = $3 || 0;
        $nr = (defined $sh->{$name})?$#{$sh->{$name}}:0
          if $nr eq '+';
        $nr = (defined $sh->{$name})?($#{$sh->{$name}} + $nr + 1):0
          if $nr < 0; 
        $name =~ s{//}{/};
        return undef unless exists $sh->{$name};
        $osh = $sh;
        $sh = $sh->{$name};
        if (ref $sh eq 'ARRAY') {
          return $sh if $c == @segs && not $2;
          die "_subhash: path '$path' not specific enough: ".xml_string($osh)
            unless $2 || @{$sh} == 1;
          return undef unless exists $sh->[$nr];
          $sh = $sh->[$nr] if $2 || $c < @segs;
        }
        elsif ($2) {
          die "subhash: used '$2' where no array was found";
        }
      }
      elsif ($c == @segs && $n =~ /^([^\[]+)\[([0-9,-]+)\]$/) {
        my $name = $1;
        my $nrs = $2;
        return undef unless exists $sh->{$name};
        $sh = $sh->{$name};
        my @nrs = split /,/,$nrs;
        my @results;
        foreach my $nr (@nrs) {
          if ($nr =~ /^\d+$/) {
            push @results, $sh->[$nr];
          }
          elsif ($nr =~ /^(\d*)-(\d*)$/ && (length $1 + length $2) > 0) {
            my $min = $1 || 0;
            my $max = (length($2) && $2 < @{$sh})?$2:(@{$sh}-1);
            push @results, @{$sh}[$min..$max] if $min <= $max;
          }
          else {
            die "subhash: path '$path' does not exist";
          }
        }
        return \@results;
      }
      elsif ($n =~ /^([^\[]+)\[(\w+)="([^"]+)"\]$/) {
        my $name = $1;
        my $attrn = '@'.$2;
        my $attrv = $3;
        return undef unless exists $sh->{$name};
        $sh = $sh->{$name};
        my @results;
        foreach my $sha (@{$sh}) {
          push @results, $sha 
            if exists $sha->{$attrn} && $sha->{$attrn} eq $attrv;
        } 

        if (@results > 1) {
          die "_subhash: path '$path' not specific enough"
            if $c != @segs;
          return \@results;
        }
        $sh = $results[0]; 
      }
      else {
        die "subhash: path incorrect";
      }
    }
    elsif (ref $sh eq '') {
      return $sh;
    }
    else {
      die "subhash: structure failure";
    }
  }
  return $sh;
}

sub add_to_path($$;$) {
  my $hash = shift;
  my $path = shift;
  my $value = shift;
  my $sh = $hash;
  my $order = 0;

  my @segs = split m{(?<!/)/(?!/)}, $path;
  my $c = 0;
  foreach my $n (@segs) {
    $c++;
    if (ref $sh eq 'HASH') {
      if (not exists $sh->{'_order_'}) {
        $sh->{'_order_'} = $order++;
      }
      foreach my $key (keys %{$sh}) {
        $order = $sh->{$key}[0]{'_order_'} + 1
          if exists $sh->{$key}[0]{'_order_'} &&
             $sh->{$key}[0]{'_order_'} >= $order;
      }
      if ($n =~ /^([^\[]+)(\[(-?\d+|\+)\])?$/) {
        my $name = $1;
        my $nr = $3 || 0;
        $nr = (defined $sh->{$name})?($#{$sh->{$name}} + 1):0
          if $nr eq '+';
        $nr = (defined $sh->{$name})?($#{$sh->{$name}} + $nr + 1):0
          if $nr < 0; 
        $name =~ s{//}{/};
        if ($name =~ /^@/) {
          if ($c != @segs || $n =~ /\[/) {
            die "add_to_path: path $path incorrect; only attribute as string allowed\n";
          }
          $sh->{$name} = $value;
          return;
        }
        if (not exists $sh->{$name}) {
          $sh->{$name} = [];
        }
        $sh = $sh->{$name};
        if (ref $sh eq 'ARRAY') {
          foreach my $item (@{$sh}) {
            if (exists $item->{'_order_'}) {
              $order = $item->{'_order_'} + 1 if $item->{'_order_'} >= $order;
            }
          }
          if (not exists $sh->[$nr]) {
            $sh->[$nr] = {};
          }
          $sh = $sh->[$nr];
          if ($c == @segs) {
            return unless defined $value;
            if (exists $sh->{'_order_'}) {
              $order = $sh->{'_order_'} + 1;
            }
            else {
              $sh->{'_order_'} = $order++;
            }
            if (exists $sh->{'#all'}) {
              foreach my $item (@{$sh->{'#all'}}) {
                if (exists $item->{'_order_'}) {
                  $order = $item->{'_order_'} + 1 if $item->{'_order_'} >= $order;
                }
              } 
            }
            else { 
              $sh->{'#all'} = [];
            }
            $sh = $sh->{'#all'};
            push @{$sh}, {'#text' => $value, '_order_' => $order++};   
            return;
          }
        }
        elsif ($2) {
          die "add_to_path: used '$2' where no array was found";
        }
      }
      else {
        die "subhash: path incorrect";
      }
    }
    else {
      die "subhash: structure failure";
    }
  }
  return;
}

sub xml_doc_string($) {
  my $hash = shift;
  my $result = '';

  my $version = $hash->{'_xml_version_'} || '1.0';
  my $encoding = $hash->{'_xml_encoding_'} || 'UTF-8';

  $result = "<?xml version=\"$version\" encoding=\"$encoding\" ?>";  
  $result .= _xml_string($hash, $encoding);

  return $result;
}

sub xml_string($;$) {
  my $hash = shift;
  my $encoding = shift;

  $encoding = $hash->{'_xml_encoding_'} unless defined $encoding;
  return _xml_string($hash, $encoding); 
}

sub _xml_string($$;$$$) {
  my $hash = shift;
  my $encoding = shift;
  my $tag = shift;
  my $depth = shift;
  my $asked4data = shift;
  my @results;
  my $attr_string = '';
  my $result_string = '';

  foreach my $hash_key (keys %{$hash}) {
    next if $hash_key =~ '^_.+_$';
    if ($hash_key =~ '^#') {
      _text($hash->{$hash_key}, \@results, $encoding, $asked4data);
      next;
    }
    elsif ($hash_key =~ '^@') {
      $attr_string .= ' '.substr($hash_key,1).'="';
      if ($asked4data) {
        $attr_string .= $hash->{$hash_key}.'"';
      }
      else {
        $attr_string .= _char_encode($hash->{$hash_key}, $encoding).'"';
      }
      next;
    }
    foreach my $inner_hash (@{$hash->{$hash_key}}) {
      my $inner_result = _xml_string($inner_hash, $encoding, $hash_key, $depth+1, $asked4data);
      my $index = $inner_hash->{'_order_'};
      $index++ while(exists $results[$index]);
      $results[$index] = $inner_result;
    }
  }
  if ($tag) {
    $result_string .= "<$tag";
    $result_string .= $attr_string;
  }
  @results = grep {defined} @results;
  if(@results) {
    my $inner_result = '';
    if (grep {$_ !~ /</} @results) {
      local $" = '';
      $inner_result .= "@results";
die("Multi line value:\n$inner_result") if $inner_result =~ m/$^/; 
    }
    else {
      local $" = "\n";
      @results = map {(INDENT_STR x $depth).$_} @results;
      $inner_result = "\n@results\n";
      $inner_result .= (INDENT_STR x ($depth-1));
    }
    $inner_result = ">$inner_result" if $tag;
    $result_string .= "$inner_result";
    $result_string .= "</$tag>" if $tag;
  }
  elsif ($tag) {
    $result_string .= "/>";
  }
  return $result_string;
}

sub _ntext {
  my $array = shift;
  my $results = shift;
  my $encoding = shift;
  my $asked4data = shift;
 
  return _text($array, $results, $encoding, $asked4data, 1);
}

sub _text {
  my $array = shift;
  my $results = shift;
  my $encoding = shift;
  my $asked4data = shift;
  my $normal = shift;

  if (0) { # delete code(@{$array} == 1) {
    if ($asked4data || defined $array->[0]->{'#cdata'}) {
      if (defined $array->[0]->{'#cdata'}) {
        $results->[0] = $array->[0]->{'#cdata'};
      }
      else {
        $results->[0] = $array->[0]->{'#text'};
      }
    }
    else {
      if ($normal) {
        $results->[0] = (defined $encoding)?
                              encode($encoding, $array->[0]->{'#text'}):
                              $array->[0]->{'#text'};
      }
      else {
        chomp($results->[0] = _char_encode($array->[0]->{'#text'}, $encoding));
      }
    }
    return $results;
  }

  foreach my $th (@{$array}) {
    my $index = $th->{'_order_'};
    $index++ while(exists $results->[$index]);
    if ($asked4data || defined $th->{'#cdata'}) {
      if (defined $th->{'#cdata'}) {
        $results->[$index] = $th->{'#cdata'};
      }
      else {
        $results->[$index] = $th->{'#text'};
      }
    }
    else {
      if ($normal) {
        $results->[$index] = (defined $encoding)?
                              encode($encoding, $th->{'#text'}):
                              $th->{'#text'};
      }
      else {
        chomp($results->[$index] = _char_encode($th->{'#text'}, $encoding));
      }
    }
  }
}

sub deep_copy($) {
  my $this = shift;
  
  if (not ref $this) {
    return $this;
  }
  elsif (ref $this eq "ARRAY") {
    return [map deep_copy($_), @{$this}];
  }
  elsif (ref $this eq "HASH") {
    return +{
      map { $_ => deep_copy($this->{$_}) } keys %{$this}
    };
  }
  else {
    die("Unknown type: $this");
  }
}

#------------------------

sub checkxmlsyntax($$;$) {
  my $xml_hash = shift;
  my $grammar = shift;
  my $context = shift;

  if (ref $grammar eq 'HASH') {
    if (ref $xml_hash eq 'ARRAY') {
      foreach my $xh (@{$xml_hash}) {
        checkxmlsyntax($xh, $grammar, $context);
      }
      return;
    }
    elsif (ref $xml_hash eq '') {
      my @gk = keys %{$grammar};
      die "Expecting inside $context: @gk\n";
    }
    my %hash_keys;
    my $check_attr_only = 0;
    my $check_attr_not = 0;
    my $alternative_found;
    my $alternative = '';
    @hash_keys{grep {$_ ne '_order_'} keys %{$xml_hash}} = ();
    foreach my $key (keys %{$grammar}) {
      $check_attr_only = 1, next if $key eq '*';
      $check_attr_not = 1, next if $key eq '@*';
      if ($key =~ /^(\@)?([a-z_]+[a-z0-9_.-]*)([+*?]?)(\|?)$/i) {
        my $is_attr = length $1;
        my $element = "$1$2"; 
        my $is_alter = length $4;
        my $kind = $3;
        next if $check_attr_only && ! $is_attr;
        next if $check_attr_not && $is_attr;
        delete $hash_keys{$element};
        if ($is_alter) {
          $alternative_found = 0;
          if (exists $xml_hash->{$element}) {
            die "Alternative '$alternative_found' found, ".
                "but '$element' also exists\n"
              if $alternative_found && length $alternative;
            $alternative_found = 1;
            $alternative = $element;
            checkxmlsyntax($xml_hash->{$element}, $grammar->{$key}, "'$element'");
          } 
          else {
            $alternative_found = 1 if $kind eq '?' || $kind eq '*';
            next;
          }
        }
        my $min = ($kind eq '+' || $kind eq '')?1:0;
        my $max = ($kind eq '?' || $kind eq '')?1:2**16;
        my $count = 0;
        if(exists $xml_hash->{$element}) {
          if (ref $xml_hash->{$element} eq 'ARRAY') {
            $count = @{$xml_hash->{$element}};
          } 
          else {
            $count = 1;
          }
          checkxmlsyntax($xml_hash->{$element}, $grammar->{$key}, "'$element'"); 
        }
        if ($count < $min || $count > $max) {
          my $err = "'$element' is found $count times inside $context, ";
          if($min == $max) {
            $err .= "but must exist $min time(s)\n";
          } 
          else {
            $err .= "but must exist between $min and $max times\n";
          }
          die $err;
        }
      }
      else {
        die "Incorrect element name in grammar: '$key'\n";
      }
    }
    my @hks;
    if ($check_attr_only) {
      @hks = grep {$_ =~ '^@'} keys %hash_keys;
    }
    elsif ($check_attr_not) {
      @hks = grep {$_ !~ '^@'} keys %hash_keys;
    }
    else {
      @hks = keys %hash_keys;
    }
    if(@hks) {
      die "The following are not allowed inside $context: @hks\n";
    }
    if(defined $alternative_found && $alternative_found == 0) {
      die "No matching alternatives found in $context\n";
    }
  }
  elsif (ref $grammar eq 'ARRAY') {
    die "No arrays allowed in grammar, use only hashes!\n";
  }
  else {
    if ($grammar eq '+') {
      if (ref $xml_hash eq '' || defined $xml_hash->[0]->{'#all'}) {
        my $text = (ref $xml_hash)?text_for_path($xml_hash, ''):$xml_hash;
        if (length $text == 0) {
          my $str = ($context =~ /^('?)\@(.+)\1/)?"Attribute '$2'":$context;
          die "$str (value: '$text') must contain a non empty string\n";
        }
      }
      else {
        die "The $context must contain a (non empty) string, now $xml_hash\n";
      }
    }
    elsif ($grammar ne '*') {
      if (ref $xml_hash eq '' || defined $xml_hash->[0]->{'#all'}) {
        my $text = (ref $xml_hash)?text_for_path($xml_hash, ''):$xml_hash;
        if ($text !~ /^$grammar$/) {
          my $str = ($context =~ /^('?)\@(.+)\1/)?"Attribute '$2'":$context;
          die "$str (value: '$text') contains an improper string\n";
        }
      }
      else {
        die "The $context must contain a(n empty) string, now $xml_hash\n";
      }
    }
  }
}

1;

