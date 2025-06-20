#!/usr/bin/env -S perl -T
use v5.16;
use strict;
use warnings;
use Test::More tests => 2;
use PVE::Storage::Custom::StorPoolPlugin;

my $key = 'migratedfrom';

sub x { a(@_, 0) }
sub a { b(@_, {$key=>'mars'}) }
sub b { c(@_, 2) }
sub c { node() }
sub node { PVE::Storage::Custom::StorPoolPlugin::_get_migration_source_node() }


is( x(), 'mars', 'Migration option found' );

$key = 'other';

is( x(), undef, 'Migration option not found' );



