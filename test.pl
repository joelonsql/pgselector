#!/usr/bin/perl
use HTML;

my $HTML = HTML->new();



my $string = "this is an interpolated method call: @{[$HTML->input({Name => 'hej', Value => 'Hoho'})]}";

print $string;

