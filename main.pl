#!/usr/bin/env perl
use strict;
use warnings;

use v5.010;

use File::Temp;
use PDF::API2;

# CONFIG
use constant {
  POVRAY => '/usr/local/bin/povray37',
  DPI => 72,
  QUALITY => 4,
  ANTIALIAS => 0,
};

##############################################################################
# HELPER FUNCTIONS

# helper: choose one item from a list
sub pick { $_[int(rand(@_))] }

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
}

######################################
# Scene Generators

# Item in a lightbox
sub generate_scene_lightbox
{
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
}

######################################
# Special Generators

# Flat, single-surface (for demo fabric patterns, artwork, etc)
sub generate_surface
{
  return "plane { <0, 1, 0>, 4 }";
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

##############################################################################
# RENDER FUNCTION
#  Usage: render(script, pdf, page, x, y, w, h)
#
# Given the POV-Ray script in $script,
#  call POV-Ray and render a .png image.
# Then, import it to the pdf document,
#  create an area on page at x,y with w,h size,
#  and draw it on the PDF.
sub render
{
  my ($script, $pdf, $page, $x, $y, $w, $h) = @_;

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
  my $png = `$cmd`;
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
# Load data files
my %data;
$data{adjectives} = load('data/adjectives.txt');
$data{nouns} = load('data/nouns.txt');
$data{technologies} = load('data/technologies.txt');

# Create a blank PDF file
my $pdf = PDF::API2->new( -file => 'out.pdf' );

# Add a built-in font to the PDF
my $font = $pdf->corefont('Helvetica-Bold');

# FRONT COVER
{
  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  $page->mediabox('Letter');

  # Make a big fancy image for the background.
  render(generate_example(), $pdf, $page, 0, 0, 612, 792);

  # Add some text overlay on the page.
  my $text = $page->text();
  $text->font($font, 20);
  $text->translate(150, 700);
  $text->text('CATALOG NANOGENMO');
  $pdf->finishobjects($text, $page);
}

# TITLE PAGE
{
  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  #  US Letter at 72dpi is 612x792 pt
  $page->mediabox('Letter');

  # Add some text to the page
  my $text = $page->text();
  $text->font($font, 20);
  $text->translate(150, 700);
  $text->text('TITLE PAGE');
  $pdf->finishobjects($text, $page);
}

# CONTENT PAGES
# Loop 5 pages
for (my $i = 0; $i < 5; $i ++)
{
  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  $page->mediabox('Letter');

  # Add some text to the page
  my $text = $page->text();
  $text->font($font, 20);
  $text->translate(50, 700);

  # Create a title
  my $title = join(' ',
    pick("", pick(@{$data{adjectives}})),
    pick(@{$data{adjectives}}),
    pick(@{$data{nouns}})
  );

  # Create some ad copy
  my $description = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.';

  # Create an ID number
  my $id = join('', map { substr($_, 0, 1) } split(/ /, $title)) . int(rand(99999));

  # Create a price
  my $price = int(rand(150) + 2)  - 0.05;

  # Place text on page.
  $text->text("$title\n$description\n$title ($id) \$$price");

  # Done with text.
  $pdf->finishobjects($text);

  # Render a picture of the object.
  render(generate_example(), $pdf, $page, 50, 100, 512, 400);

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
  my $text = $page->text();
  $text->font($font, 20);
  $text->translate(150, 700);
  $text->text('ORDER FORM');
  $pdf->finishobjects($text, $page);
}

# BACK COVER
{
  # Add a blank page
  my $page = $pdf->page();
  # Set the page size
  #  US Letter at 72dpi is 612x792 pt
  $page->mediabox('Letter');

  # Add some text to the page
  my $text = $page->text();
  $text->font($font, 20);
  $text->translate(150, 700);
  $text->text('BACK COVER');
  $pdf->finishobjects($text, $page);
}

# Save the PDF
$pdf->save();
