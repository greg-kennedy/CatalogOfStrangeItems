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
  ANTIALIAS => 0,
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

# generator: make a dummy wearing clothes
sub generate_clothes
{
}

# generator: make a recursive "thing"
sub generate_object
{
  return <<'EOF';
torus {
  0.5, 0.25         // major and minor radius
  rotate -45*x      // so we can see it from the top
  pigment { Green }
}
EOF
}

######################################
# Scene Generators

# Item in a lightbox
#  Simply place it on a white surface with an area light above.
sub generate_scene_lightbox
{
  return <<'EOF';
camera {
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

######################################
# TEXT GENERATORS

# Item title / name
sub generate_name {
  return join(' ',
    pick("", pick(@{$data{adjectives}})),
    pick(@{$data{adjectives}}),
    pick(@{$data{nouns}})
  );
}

# Item description
sub generate_description {
  return 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.';
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
  my $scene = generate_header() . generate_object() . generate_scene_lightbox();
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

  #say "Placing a 2x2 block at $y (height: $h)";
  ###
  # Render a picture of the object.
  my $scene = generate_header() . generate_object() . generate_scene_lightbox();
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

  #say "Placing a 2x1 block at $y (height: $h)";
  ###
  # Render a picture of the object.
  my $scene = generate_header() . generate_object() . generate_scene_lightbox();
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

  #say "Placing a 1x3 block at $x (width: $w)";
  ###
  # Render a picture of the object.
  my $scene = generate_header() . generate_object() . generate_scene_lightbox();
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

  #say "Placing a 2x2 block at $y (height: $h)";
  ###
  # Render a picture of the object.
  my $scene = generate_header() . generate_object() . generate_scene_lightbox();
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

  #say "Placing a 1x1 block at $x,$y (w/h: $w,$h)";
  ###
  # Render a picture of the object.
  my $scene = generate_header() . generate_object() . generate_scene_lightbox();
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
# Loop 5 pages
for (my $i = 0; $i < 34; $i ++)
{
  say "page $i...";

  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  $page->mediabox('Letter');

  # Big switch block to fill each layout
  #my $layout = int(rand(6000));
  my $layout = $i;

  if ($layout == 0) {
    # full page bleed
    layout_2x3($page);
  } elsif ($layout == 1) {
    # 2x2 square, fill rest with 2x1 or a pair of 1x1
    layout_2x2($page, 0);
    layout_2x1($page, 2);
  } elsif ($layout == 2) {
    layout_2x2($page, 0);
    layout_1x1($page, 2, 0);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 3) {
    layout_2x1($page, 0);
    layout_2x2($page, 1);
  } elsif ($layout == 4) {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 0, 1);
    layout_2x2($page, 1);
  } elsif ($layout == 5) {
    # Full-height columnar layouts
    layout_1x3($page, 0);
    layout_1x3($page, 1);
  } elsif ($layout == 6) {
    layout_1x3($page, 0);
    layout_1x2($page, 0, 1);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 7) {
    layout_1x3($page, 0);
    layout_1x1($page, 0, 1);
    layout_1x2($page, 1, 1);
  } elsif ($layout == 8) {
    layout_1x3($page, 0);
    layout_1x1($page, 0, 1);
    layout_1x1($page, 1, 1);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 9) {
    layout_1x2($page, 0, 0);
    layout_1x1($page, 2, 0);
    layout_1x3($page, 1);
  } elsif ($layout == 10) {
    layout_1x1($page, 0, 0);
    layout_1x2($page, 1, 0);
    layout_1x3($page, 1);
  } elsif ($layout == 11) {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 1, 0);
    layout_1x1($page, 2, 0);
    layout_1x3($page, 1);
  } elsif ($layout == 12) {
    # 1x2 blocks with 1x1 filler
    layout_1x2($page, 0, 0);
    layout_1x1($page, 2, 0);
    layout_1x2($page, 0, 1);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 13) {
    layout_1x2($page, 0, 0);
    layout_1x1($page, 2, 0);
    layout_1x1($page, 0, 1);
    layout_1x2($page, 1, 1);
  } elsif ($layout == 14) {
    layout_1x1($page, 0, 0);
    layout_1x2($page, 1, 0);
    layout_1x2($page, 0, 1);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 15) {
    layout_1x1($page, 0, 0);
    layout_1x2($page, 1, 0);
    layout_1x1($page, 0, 1);
    layout_1x2($page, 1, 1);
  } elsif ($layout == 16) {
    # Single 1x2
    layout_1x2($page, 0, 0);
    layout_1x1($page, 2, 0);
    layout_1x1($page, 0, 1);
    layout_1x1($page, 1, 1);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 17) {
    layout_1x1($page, 0, 0);
    layout_1x2($page, 1, 0);
    layout_1x1($page, 0, 1);
    layout_1x1($page, 1, 1);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 18) {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 1, 0);
    layout_1x1($page, 2, 0);
    layout_1x2($page, 0, 1);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 19) {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 1, 0);
    layout_1x1($page, 2, 0);
    layout_1x1($page, 0, 1);
    layout_1x2($page, 1, 1);
  } elsif ($layout == 20) {
    # Mixed wide and tall rectangles
    layout_1x2($page, 0, 0);
    layout_1x2($page, 0, 1);
    layout_2x1($page, 2);
  } elsif ($layout == 21) {
    layout_2x1($page, 0);
    layout_1x2($page, 1, 0);
    layout_1x2($page, 1, 1);
  } elsif ($layout == 22) {
    # Very broken layouts
    layout_1x2($page, 0, 0);
    layout_1x1($page, 0, 1);
    layout_1x1($page, 1, 1);
    layout_2x1($page, 2);
  } elsif ($layout == 23) {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 1, 0);
    layout_1x2($page, 0, 1);
    layout_2x1($page, 2);
  } elsif ($layout == 24) {
    layout_2x1($page, 0);
    layout_1x2($page, 1, 0);
    layout_1x1($page, 1, 1);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 25) {
    layout_2x1($page, 0);
    layout_1x1($page, 1, 0);
    layout_1x1($page, 2, 0);
    layout_1x2($page, 1, 1);
  } elsif ($layout == 26) {
    # Various combinations of 2x1 blocks
    layout_2x1($page, 0);
    layout_2x1($page, 1);
    layout_2x1($page, 2);
  } elsif ($layout == 27) {
    layout_2x1($page, 0);
    layout_2x1($page, 1);
    layout_1x1($page, 2, 0);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 28) {
    layout_2x1($page, 0);
    layout_1x1($page, 1, 0);
    layout_1x1($page, 1, 1);
    layout_2x1($page, 2);
  } elsif ($layout == 29) {
    layout_2x1($page, 0);
    layout_1x1($page, 1, 0);
    layout_1x1($page, 1, 1);
    layout_1x1($page, 2, 0);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 30) {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 0, 1);
    layout_2x1($page, 1);
    layout_2x1($page, 2);
  } elsif ($layout == 31) {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 0, 1);
    layout_2x1($page, 1);
    layout_1x1($page, 2, 0);
    layout_1x1($page, 2, 1);
  } elsif ($layout == 32) {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 0, 1);
    layout_1x1($page, 1, 0);
    layout_1x1($page, 1, 1);
    layout_2x1($page, 2);
  } else {
    layout_1x1($page, 0, 0);
    layout_1x1($page, 0, 1);
    layout_1x1($page, 1, 0);
    layout_1x1($page, 1, 1);
    layout_1x1($page, 2, 0);
    layout_1x1($page, 2, 1);
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
