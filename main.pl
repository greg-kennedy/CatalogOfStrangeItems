#!/usr/bin/env perl
use strict;
use warnings;

use v5.010;

use File::Temp;
use PDF::API2;

##############################################################################
# CONFIG
use constant {
  POVRAY => '/usr/local/bin/povray37',
  DPI => 72,
  QUALITY => 9,
  ANTIALIAS => 1,

  PAGES => 20,
};

# layout dimensions etc
#  MARGIN => 36,
#  PAGE_W => 612,
#  PAGE_H => 792,

##############################################################################
# GLOBAL VARIABLES
our %data;

our $pdf;
our %font;

##############################################################################
# HELPER FUNCTIONS

# helper: choose one item from a list
sub pick { $_[int(rand(@_))] }
# choose item with probability X
#sub chance { rand() < $_[0] }

# helper: load a data file and return it
sub load
{
  my @data;
  open (my $fp, '<', $_[0]) or die "Couldn't open file $_[0]: $!";
  while (my $line = <$fp>) {
    chomp $line;
    push @data, $line;
  }
  close $fp;
  return \@data;
}

##############################################################################
# GENERATORS
#  The functions here do different types of generation for the povray scene.
#  Roughly grouped by utility.

######################################
# Texture / Surface Generators

# helper: pass a 3-component array and get back a bracketed print representation
sub vect
{
  return ' <' . join(',', @_) . '> ';
}

# helper: given a point and a radius, choose a new random point on the sphere surface
sub point_on_sphere
{
  my ($x, $y, $z, $r) = @_;

  my ($new_x, $new_y, $new_z) = (0, 0, 0);
  for (my $q = 0; $q < 15; $q ++) {
    $new_x += rand($r) - ($r / 2);
    $new_y += rand($r) - ($r / 2);
    $new_z += rand($r) - ($r / 2);
  }

  my $dist = sqrt($new_x * $new_x + $new_y * $new_y + $new_z * $new_z);

  return ($x + $new_x / $dist, $y + $new_y / $dist, $z + $new_z / $dist);
}

# Generate random color
sub generate_color
{
  return "rgb <" . rand() . ", " . rand() . ", " . rand() . ">";
}

# Generate random texture
sub generate_texture
{
  return <<'EOF';
texture {
  pigment {
    checker rgb<1,0,0>, color rgb<0,0,1>
  }
  finish {
    ambient rgb<1,1,1>
  }
}
EOF
}

######################################
# Object Generators

# generator: make a recursive "thing"
sub generate_object
{
  # get x/y coords of object "base"
  my $x = shift || 0;
  my $y = shift || 0;
  my $z = shift || 0;

  # avoid deep recursion
  my $depth = shift || 0;
  if ($depth > 5) { return "" }

  # all 3.7.0 objects
  my $object = pick( 'blob' ); #, 'box', 'cone', 'cylinder', 'height_field', 'isosurface', 'julia_fractal', 'lathe', 'ovus', 'parametric', 'prism', 'sphere', 'sphere_sweep', 'superellipsoid', 'sor', 'text', 'torus' );

  # script fragment we will return at the end
  #  and array of subobjects connected here
  my @subobjects;
  my $script = $object . " {\n";

  # BLOB type: made of smaller objects
  if ($object eq 'blob') {
    # at least first should hit the xyz point
    $script .= "threshold " . rand() . "\n";
    my $radius = rand(2);
    $script .= "  sphere { " . vect($x,$y,$z) . ", " . $radius . " 1 " . generate_texture() . " }\n";

    # the rest can scatter all over, each may be a connection point to something else
    for (my $i = 0; $i < int(rand(5)); $i ++)
    {
      my ($new_x, $new_y, $new_z) = point_on_sphere($x, $y, $z, $radius + rand(2));
      my $r2 = rand(1);
      $script .= "  sphere { " . vect($new_x,$new_y,$new_z) . ", " . $r2 . " 1 " . generate_texture() . " }\n";
    }
  } elsif ($object eq 'torus') {
    $script .= "  0.5, 0.25\n  rotate -45*x\n  pigment { Green }\n";
  }

  # subobjects happen here
  #for (my $i = 0; $i < int(rand(5)); $i ++)
  #{
  #  my $subobj = generate_object($x, $y, $z, $depth + 1);
  #  if ($subobj) { $script .= ("  " x $depth) . $subobj . "\n" }
    #$script .= "  sphere { <$x,$y,$z>, " . rand() . " 1 " . generate_texture() . " }\n";
  #}

  # terminate object
  $script .= "}";

  return $script;
}

######################################
# Scene Generators

# Item in a lightbox
#  Simply place it on a white surface with an area light above.
sub generate_scene_lightbox
{
  return <<'EOF';
camera {
  up y * image_height
  right x * image_width
  location <0, 2, -2>
  look_at <0, 0, 0>
  angle 45
}
background {
  color White
}
plane {
  y, 0
  pigment { color White }
}
light_source {
  4 * y
  color White
  area_light 4 * x, 4 * z, 3, 3
  adaptive 1
  jitter
}
EOF
}

# Item on a shelf
sub generate_scene_shelf
{
}

# Item on a counter
sub generate_scene_counter
{
}

# Item in a yard
sub generate_scene_yard
{
  return <<'EOF';
camera {
  location <0, 1, -8>
  look_at <0, 0, 0>
  angle 45
}
light_source {
  <8, 8, -8>
  color White
}
// sky ---------------------------------------------------------------------
plane{<0,1,0>,1 hollow
       texture{ pigment{ bozo turbulence 0.76
                         color_map { [0.5 rgb <0.20, 0.20, 1.0>]
                                     [0.6 rgb <1,1,1>]
                                     [1.0 rgb <0.5,0.5,0.5>]}
                       }
                finish {ambient 1 diffuse 0} }
       scale 10000}
// fog ---------------------------------------------------------------------
fog{fog_type   2
    distance   50
    color      White
    fog_offset 0.1
    fog_alt    2.0
    turbulence 0.8}
// ground ------------------------------------------------------------------
plane { y, 0
        texture{ pigment{color rgb<0.35,0.65,0.0>}
                 normal {bumps 0.75 scale 0.001}
               }
      }
EOF
}

######################################
# Special Generators

# Flat, single-surface (for demo fabric patterns, artwork, etc)
sub generate_surface
{
  # default camera sits at <0,0,0> and points at <0,0,1>
  return <<'EOF';
#version 3.7;
global_settings { assumed_gamma 1.0 }
camera {
  orthographic
}
plane {
  -z, -1
  texture {
    pigment {
      checker rgb<1,0,0>, color rgb<0,0,1>
    }
    finish {
      ambient rgb<1,1,1>
    }
  }
}
EOF
}

# Example file
sub generate_example
{
return <<'EOF';
#version 3.7;
#include "colors.inc"
global_settings { assumed_gamma 1.0 }
background { color Cyan }
camera {
  location <0, 2, -3>
  look_at  <0, 1,  2>
}
sphere {
  <0, 1, 2>, 2
  texture {
    pigment { color Yellow }
  }
}
light_source { <2, 4, -3> color White}
EOF
}

# The header files and default info for every POV scene
sub generate_header {
  return <<'EOF';
#version 3.7;
#include "colors.inc"
global_settings { assumed_gamma 1.0 }
EOF
}

# complete scene
sub generate_scene {
  # default header
  my $final_scene = generate_header();

  # background items
  my $location = pick('yard', 'lightbox');
  if ($location eq 'yard') {
    $final_scene .= generate_scene_yard();
  } else {
    $final_scene .= generate_scene_lightbox();
  }

  # the object
  $final_scene .= generate_object();

  return $final_scene;
}

######################################
# TEXT GENERATORS

# Item title / name
sub generate_name {
  return
    pick("", pick(@{$data{adjectives}}) . ' ') .
    pick(@{$data{adjectives}}) . ' ' .
    pick(@{$data{nouns}});
}

# Grammar bits, which can be strung together to make larger phrases
#  Create some "action" you can perform with the object
sub generate_action {
  return pick(@{$data{verbs}}) . ' ' . pick('a','the','your','any') . ' ' . pick(@{$data{nouns}});
}

# Item description: one paragraph
sub generate_description {
  my $intro = pick('At last', "It's back", 'The latest in ' . pick(@{$data{technologies}}), 'Behold', 'Check this out') . pick('!',':',' -');

  # some features
  my $features = '';
  for (my $i = 0; $i < 3; $i ++)
  {
    my $action = pick('Now you can ', 'Allows you to ', 'Designed to ', 'Made to ', 'Enables you to ', "It's a snap to ") . generate_action() . pick('.','!');
    my $feature = pick('Features','Featuring a','Sports a','Includes a','Boasting a') . ' ' . pick(@{$data{adjectives}}) . ' ' . pick(@{$data{nouns}}) . '.';

    $features = $features . pick($action, $feature) . ' ';
  }


  my $requires = 'Requires ' . pick(int(rand(10)) . ' ' . pick('AA','AAA','D') . ' batteries', pick('a', 'one', pick(@{$data{adjectives}}) . ' ' . pick(@{$data{nouns}}))) . ' (not included)';
  my $weight = 'Weight: ' . int(rand(30)) . ' pounds.';
  my $size = 'Size: ' . int(rand(30)) . 'x' . int(rand(30)) . 'x' . int(rand(30));
  my $age = 'Ages ' . int(rand(18)) . pick(' and up','+', '-' . int(rand(130)));

  # join all and return
  return join(' ', $intro, $features, pick($requires, $weight, $size, $age));
}

# Item price
sub generate_price {
  return int(rand(150) + 2)  - 0.05;
}

##############################################################################
# RENDER FUNCTION
#  Usage: render(script, page, x, y, w, h)
#
# Given the POV-Ray script in $script,
#  call POV-Ray and render a .png image.
# Then, import it to the pdf document,
#  create an area on page at x,y with w,h size,
#  and draw it on the PDF.
sub render
{
  my ($script, $page, $x, $y, $w, $h) = @_;

  # Create a POV-Ray script
  #  POV-Ray will not read from stdin (despite what the manual says)
  #  so use a temp file instead.
  my $tmp = File::Temp->new( SUFFIX => '.pov' );
  # Write the supplied script to the file.
  print $tmp $script;
  # Close file, no more writing
  close $tmp;

  # RENDER COMMAND
  #  Adjust quality settings here (antialiasing, etc)
  my $cmd = POVRAY . ' +I' . $tmp->filename . ' +O- -GD -GR -GS -RVP +W' . int($w*DPI/72) . ' +H' . int($h*DPI/72) . ' +Q' . QUALITY;
  if (ANTIALIAS) {
    $cmd .= ' +A';
  }
  # Call POV-Ray to render it, result goes to stdout which we capture
  my $png = `$cmd 2>/dev/null`;
  if (! $png) {
    die "ERROR: POV-Ray returned empty image. Script was:\n$script";
  }
  # hook filehandle to scalar and import to PDF
  open (my $sh, '<', \$png) or die "Could not open scalar as filehandle: $!";
  my $image = $pdf->image_png($sh);
  close ($sh);

  # Create a gfx object on the page
  my $gfx = $page->gfx();
  # Place it at the specified coords
  $gfx->image($image, $x, $y, $w, $h);
  # All done.
  $pdf->finishobjects($gfx);
}

##############################################################################
# TEXT FUNCTION
#  Usage: text(string, page, {parameters})
#
# Write STRING onto PAGE.
# Strings are split on space, then reassembled to fit within param{w},
#  advancing to next line if needed.
sub text
{
  my $string = shift;
  my $page = shift;
  my $x = shift;
  my $y = shift;

  # set parameter hash defaults, then override with supplied values
  my %param = (
    font => $font{'helvetica'},
    size => 12,
    w => 540,
    h => 720,
    align => 'left',
    %{+shift}
  );

  # split line into component words
  my @words = split /\s/, $string;

  # Fill words in the bounding box
  while (@words) # && ($y < $param{h}))
  {
    # Make a text box, set font and position
    my $text = $page->text();
    $text->font($param{font}, $param{size});
    $text->translate($x, $y);

    # Repeatedly put words until the string won't fit any more
    my $line = shift @words;
    while (@words) {
      if ($text->advancewidth($line . ' ' . $words[0]) < $param{w}) {
        $line = $line . ' ' . shift(@words);
      } else {
        last;
      }
    }

    # Put text onto page
    if ($param{align} eq 'center') {
      $text->text_center($line);
    } elsif ($param{align} eq 'right') {
      $text->text_right($line);
    } else {
      $text->text($line);
    }
    $pdf->finishobjects($text);

    # advance
    $y -= $param{size};
  }

  return $y;
}

##############################################################################
# LAYOUT
#  The functions here do layout of a block on the page

# Global definition of all available layouts (const)
use constant LAYOUTS => (
  [
    # full page bleed
    ['2x3'],
  ], [
    # 2x2 square, fill rest with 2x1 or a pair of 1x1
    ['2x2', 0],
    ['2x1', 2],
  ], [
    ['2x2', 0],
    ['1x1', 2, 0],
    ['1x1', 2, 1],
  ], [
    ['2x1', 0],
    ['2x2', 1],
  ], [
    ['1x1', 0, 0],
    ['1x1', 0, 1],
    ['2x2', 1],
  ], [
    # Full-height columnar layouts
    ['1x3', 0],
    ['1x3', 1],
  ], [
    ['1x3', 0],
    ['1x2', 0, 1],
    ['1x1', 2, 1],
  ], [
    ['1x3', 0],
    ['1x1', 0, 1],
    ['1x2', 1, 1],
  ], [
    ['1x3', 0],
    ['1x1', 0, 1],
    ['1x1', 1, 1],
    ['1x1', 2, 1],
  ], [
    ['1x2', 0, 0],
    ['1x1', 2, 0],
    ['1x3', 1],
  ], [
    ['1x1', 0, 0],
    ['1x2', 1, 0],
    ['1x3', 1],
  ], [
    ['1x1', 0, 0],
    ['1x1', 1, 0],
    ['1x1', 2, 0],
    ['1x3', 1],
  ], [
    # 1x2 blocks with 1x1 filler
    ['1x2', 0, 0],
    ['1x1', 2, 0],
    ['1x2', 0, 1],
    ['1x1', 2, 1],
  ], [
    ['1x2', 0, 0],
    ['1x1', 2, 0],
    ['1x1', 0, 1],
    ['1x2', 1, 1],
  ], [
    ['1x1', 0, 0],
    ['1x2', 1, 0],
    ['1x2', 0, 1],
    ['1x1', 2, 1],
  ], [
    ['1x1', 0, 0],
    ['1x2', 1, 0],
    ['1x1', 0, 1],
    ['1x2', 1, 1],
  ], [
    # Single 1x2
    ['1x2', 0, 0],
    ['1x1', 2, 0],
    ['1x1', 0, 1],
    ['1x1', 1, 1],
    ['1x1', 2, 1],
  ], [
    ['1x1', 0, 0],
    ['1x2', 1, 0],
    ['1x1', 0, 1],
    ['1x1', 1, 1],
    ['1x1', 2, 1],
  ], [
    ['1x1', 0, 0],
    ['1x1', 1, 0],
    ['1x1', 2, 0],
    ['1x2', 0, 1],
    ['1x1', 2, 1],
  ], [
    ['1x1', 0, 0],
    ['1x1', 1, 0],
    ['1x1', 2, 0],
    ['1x1', 0, 1],
    ['1x2', 1, 1],
  ], [
    # Mixed wide and tall rectangles
    ['1x2', 0, 0],
    ['1x2', 0, 1],
    ['2x1', 2],
  ], [
    ['2x1', 0],
    ['1x2', 1, 0],
    ['1x2', 1, 1],
  ], [
    # Very broken layouts
    ['1x2', 0, 0],
    ['1x1', 0, 1],
    ['1x1', 1, 1],
    ['2x1', 2],
  ], [
    ['1x1', 0, 0],
    ['1x1', 1, 0],
    ['1x2', 0, 1],
    ['2x1', 2],
  ], [
    ['2x1', 0],
    ['1x2', 1, 0],
    ['1x1', 1, 1],
    ['1x1', 2, 1],
  ], [
    ['2x1', 0],
    ['1x1', 1, 0],
    ['1x1', 2, 0],
    ['1x2', 1, 1],
  ], [
    # Various combinations of 2x1 blocks
    ['2x1', 0],
    ['2x1', 1],
    ['2x1', 2],
  ], [
    ['2x1', 0],
    ['2x1', 1],
    ['1x1', 2, 0],
    ['1x1', 2, 1],
  ], [
    ['2x1', 0],
    ['1x1', 1, 0],
    ['1x1', 1, 1],
    ['2x1', 2],
  ], [
    ['2x1', 0],
    ['1x1', 1, 0],
    ['1x1', 1, 1],
    ['1x1', 2, 0],
    ['1x1', 2, 1],
  ], [
    ['1x1', 0, 0],
    ['1x1', 0, 1],
    ['2x1', 1],
    ['2x1', 2],
  ], [
    ['1x1', 0, 0],
    ['1x1', 0, 1],
    ['2x1', 1],
    ['1x1', 2, 0],
    ['1x1', 2, 1],
  ], [
    ['1x1', 0, 0],
    ['1x1', 0, 1],
    ['1x1', 1, 0],
    ['1x1', 1, 1],
    ['2x1', 2],
  ], [
    ['1x1', 0, 0],
    ['1x1', 0, 1],
    ['1x1', 1, 0],
    ['1x1', 1, 1],
    ['1x1', 2, 0],
    ['1x1', 2, 1],
  ]
);

# Full page spread (2x3)
sub layout_2x3
{
  my $page = shift;

  # dimensions on page in pt
  my $x = 36;
  my $y = 756;
  my $w = 540;
  my $h = 720;

  ###
  # Render a picture of the object.
  my $scene = generate_scene();
  render($scene, $page, $x, $y - $h, $w, $h);

  # Add some text to the page
  $y -= 16;
  # Create a title
  my $title = generate_name();
  $y = text($title, $page, $x, $y, { font => $font{helvetica_bold}, size => 16 });

  # Create some ad copy
  my $description = generate_description();
  $y = text($description, $page, $x, $y, { size => 14, w => $w });

  # Create an ID number
  my $id = join('', map { uc(substr($_, 0, 1)) } split(/ /, $title)) . int(rand(99999));
  # Create a price
  my $price = generate_price();
  # Place text on page.
  $y = text("$id | $price", $page, $x, $y, { font => $font{helvetica_bold}, size => 14 });
}

# 2x2 square layout
sub layout_2x2
{
  my ($page, $row) = @_;

  my $x = 36;
  my $w = 540;

  # compute box height, which should be 2/3 of a full page,
  #  less a margin and a half
  my $h = 468;
  my $y;
  if ($row == 0) {
    $y = 756;
  } else {
    $y = 504;
  }

  ###
  # Render a picture of the object.
  my $scene = generate_scene();
  render($scene, $page, $x, $y - $h, $w, $h);

  # Add some text to the page
  $y -= 16;
  # Create a title
  my $title = generate_name();
  $y = text($title, $page, $x, $y, { font => $font{helvetica_bold}, size => 16 });

  # Create some ad copy
  my $description = generate_description();
  $y = text($description, $page, $x, $y, { size => 14, w => $w });

  # Create an ID number
  my $id = join('', map { uc(substr($_, 0, 1)) } split(/ /, $title)) . int(rand(99999));
  # Create a price
  my $price = generate_price();
  # Place text on page.
  $y = text("$id | $price", $page, $x, $y, { font => $font{helvetica_bold}, size => 14 });
}

# 2x1 wide rectangular layout
sub layout_2x1
{
  my ($page, $row) = @_;

  my $x = 36;
  my $w = 540;

  # compute box height, which should be 1/3 of a full page, less margins
  my $h = 216;
  my $y;
  if ($row == 0) {
    $y = 756;
  } elsif ($row == 1) {
    $y = 504;
  } else {
    $y = 252;
  }

  ###
  # Render a picture of the object.
  my $scene = generate_scene();
  render($scene, $page, $x, $y - $h, $w, $h);

  # Add some text to the page
  $y -= 16;
  # Create a title
  my $title = generate_name();
  $y = text($title, $page, $x, $y, { font => $font{helvetica_bold}, size => 16 });

  # Create some ad copy
  my $description = generate_description();
  $y = text($description, $page, $x, $y, { size => 14, w => $w });

  # Create an ID number
  my $id = join('', map { uc(substr($_, 0, 1)) } split(/ /, $title)) . int(rand(99999));
  # Create a price
  my $price = generate_price();
  # Place text on page.
  $y = text("$id | $price", $page, $x, $y, { font => $font{helvetica_bold}, size => 14 });
}

# 1x3 tall whole-column layout
sub layout_1x3
{
  my ($page, $col) = @_;

  my $y = 756;
  my $h = 720;

  # compute box width, which is 1/2 a full page, minus center + edge margins
  my $w = 252;
  my $x;
  if ($col == 0) {
    $x = 36;
  } else {
    $x = 324;
  }

  ###
  # Render a picture of the object.
  my $scene = generate_scene();
  render($scene, $page, $x, $y - $h, $w, $h);

  # Add some text to the page
  $y -= 16;
  # Create a title
  my $title = generate_name();
  $y = text($title, $page, $x, $y, { font => $font{helvetica_bold}, size => 16 });

  # Create some ad copy
  my $description = generate_description();
  $y = text($description, $page, $x, $y, { size => 14, w => $w });

  # Create an ID number
  my $id = join('', map { uc(substr($_, 0, 1)) } split(/ /, $title)) . int(rand(99999));
  # Create a price
  my $price = generate_price();
  # Place text on page.
  $y = text("$id | $price", $page, $x, $y, { font => $font{helvetica_bold}, size => 14 });
}

# 1x2 tall column
sub layout_1x2
{
  my ($page, $row, $col) = @_;

  # compute box width, which is 1/2 a full page, minus center + edge margins
  my $w = 252;
  my $x;
  if ($col == 0) {
    $x = 36;
  } else {
    $x = 324;
  }

  # compute box height, which should be 2/3 of a full page,
  #  less a margin and a half
  my $h = 468;
  my $y;
  if ($row == 0) {
    $y = 756;
  } else {
    $y = 504;
  }

  ###
  # Render a picture of the object.
  my $scene = generate_scene();
  render($scene, $page, $x, $y - $h, $w, $h);

  # Add some text to the page
  $y -= 16;
  # Create a title
  my $title = generate_name();
  $y = text($title, $page, $x, $y, { font => $font{helvetica_bold}, size => 16 });

  # Create some ad copy
  my $description = generate_description();
  $y = text($description, $page, $x, $y, { size => 14, w => $w });

  # Create an ID number
  my $id = join('', map { uc(substr($_, 0, 1)) } split(/ /, $title)) . int(rand(99999));
  # Create a price
  my $price = generate_price();
  # Place text on page.
  $y = text("$id | $price", $page, $x, $y, { font => $font{helvetica_bold}, size => 14 });
}

# Single block 1x1 layout
sub layout_1x1
{
  my ($page, $row, $col) = @_;

  # compute box height, which should be 1/3 of a full page, less margins
  my $h = 216;
  my $y;
  if ($row == 0) {
    $y = 756;
  } elsif ($row == 1) {
    $y = 504;
  } else {
    $y = 252;
  }

  # compute box width, which is 1/2 a full page, less margins
  my $w = 252;
  my $x;
  if ($col == 0) {
    $x = 36;
  } else {
    $x = 324;
  }

  ###
  # Render a picture of the object.
  my $scene = generate_scene();
  render($scene, $page, $x, $y - $h, $w, $h);

  # Add some text to the page
  $y -= 14;
  # Create a title
  my $title = uc(generate_name());
  $y = text($title, $page, $x, $y, { font => $font{helvetica_bold}, size => 14, w => $w });

  # Create some ad copy
  my $description = generate_description();
  $y = text($description, $page, $x, $y, { size => 12, w => $w });

  # Create an ID number
  my $id = join('', map { uc(substr($_, 0, 1)) } split(/ /, $title)) . int(rand(99999));
  # Create a price
  my $price = generate_price();
  # Place text on page.
  $y = text("$id | $price", $page, $x, $y, { font => $font{helvetica_bold}, size => 12 });
}

##############################################################################
##############################################################################
##############################################################################
# MAIN ENTRY POINT
##############################################################################
##############################################################################
##############################################################################

##############################################################################
#  Load data files
$data{adjectives} = load('data/adjectives.txt');
$data{nouns} = load('data/nouns.txt');
$data{verbs} = load('data/verbs.txt');
$data{technologies} = load('data/technologies.txt');

# Create a blank PDF file
$pdf = PDF::API2->new( -file => 'out.pdf' );
#$pdf->preferences( -twocolumnright => 1, -duplexfliplongedge => 1 );

# Add some built-in fonts to the PDF
$font{helvetica} = $pdf->corefont('Helvetica');
$font{helvetica_bold} = $pdf->corefont('Helvetica-Bold');
#$font{courier} = $pdf->corefont('Courier');

# FRONT COVER
{
  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  $page->mediabox('Letter');

  # Make a big fancy image for the background.
  render(generate_surface(), $page, 0, 0, 612, 792);

  # Add some text overlay on the page.
  text('Catalog of Strange Items', $page, 306, 700, { font => $font{helvetica_bold}, size => 50, align => 'center' });

  # Done with the page
  $pdf->finishobjects($page);
}

# TITLE PAGE
{
  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  #  US Letter at 72dpi is 612x792 pt
  $page->mediabox('Letter');

  # Add some text to the page
  text('TITLE PAGE', $page, 306, 700, { font => $font{helvetica_bold}, size => 20, align => 'center' });
  text('A NaNoGenMo 2018 entry.', $page, 306, 680, { font => $font{helvetica}, size => 16, align => 'center' });
  text('Written by the open-source "Catalog of Strange Items" software', $page, 306, 660, { font => $font{helvetica}, size => 16, align => 'center' });
  text('(https://github.com/greg-kennedy/CatalogOfStrangeItems),', $page, 306, 640, { font => $font{helvetica}, size => 16, align => 'center' });
  text('by Greg Kennedy (kennedy.greg@gmail.com).', $page, 306, 620, { font => $font{helvetica}, size => 16, align => 'center' });

  text('Generated on ' . scalar(localtime()) . '.', $page, 306, 100, { font => $font{helvetica}, size => 16, align => 'center' });

  # Done with the page
  $pdf->finishobjects($page);
}

# CONTENT PAGES
# Loop N pages
for (my $i = 0; $i < PAGES; $i ++)
{
  say "page $i...";

  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  $page->mediabox('Letter');

  # Big switch block to fill each layout
  my $pattern = (LAYOUTS)[int(rand(scalar(LAYOUTS)))];

  for (my $j = 0; $j < scalar @$pattern; $j ++) {
    my $block = $pattern->[$j];

    say " . block $j of " . scalar(@$pattern) . " (type " . $block->[0] . ")";

    if ($block->[0] eq '2x3') {
      layout_2x3($page);
    } elsif ($block->[0] eq '2x2') {
      layout_2x2($page, $block->[1]);
    } elsif ($block->[0] eq '2x1') {
      layout_2x1($page, $block->[1]);
    } elsif ($block->[0] eq '1x3') {
      layout_1x3($page, $block->[1]);
    } elsif ($block->[0] eq '1x2') {
      layout_1x2($page, $block->[1], $block->[2]);
    } else {
      layout_1x1($page, $block->[1], $block->[2]);
    }
  }

  # done with page!
  $pdf->finishobjects($page);
}

# ORDER FORM
{
  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  #  US Letter at 72dpi is 612x792 pt
  $page->mediabox('Letter');

  # Add some text to the page
  text('ORDER FORM', $page, 306, 700, { font => $font{helvetica_bold}, size => 20, align => 'center' });

  # Done with the page
  $pdf->finishobjects($page);
}

# BACK COVER
{
  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  #  US Letter at 72dpi is 612x792 pt
  $page->mediabox('Letter');

  # Add some text to the page
  text('BACK COVER', $page, 306, 700, { font => $font{helvetica_bold}, size => 20, align => 'center' });

  $pdf->finishobjects($page);
}

# Save the PDF
$pdf->save();
