# Copyright (c) 2016  Timm Murray
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice, 
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright 
#       notice, this list of conditions and the following disclaimer in the 
#       documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
# POSSIBILITY OF SUCH DAMAGE.
package Game::Asset;

# ABSTRACT: Load assets (images, music, etc.) for games
use strict;
use warnings;
use Moose;
use namespace::autoclean;

use Game::Asset::Type;
use Game::Asset::Null;
use Game::Asset::PerlModule;
use Game::Asset::PlainText;
use Game::Asset::YAML;

use Archive::Zip qw( :ERROR_CODES );
use YAML ();


has 'file' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);
has 'mappings' => (
    is => 'ro',
    isa => 'HashRef[ClassName]',
    default => sub {{}},
    auto_deref => 1,
);
has 'entries' => (
    is => 'ro',
    isa => 'ArrayRef[Game::Asset::Type]',
    default => sub {[]},
    auto_deref => 1,
);
has '_entries_by_shortname' => (
    traits => ['Hash'],
    is => 'ro',
    isa => 'HashRef[Game::Asset::Type]',
    default => sub {{}},
    handles => {
        get_by_name => 'get',
    },
);
has '_zip' => (
    is => 'ro',
    isa => 'Archive::Zip',
);


sub BUILDARGS
{
    my ($class, $args) = @_;
    my $file = $args->{file};

    my $zip = $class->_read_zip( $file );
    $args->{'_zip'} = $zip;

    my $index = $class->_read_index( $zip, $file );
    $args->{mappings} = {
        yml => 'Game::Asset::YAML',
        txt => 'Game::Asset::PlainText',
        pm => 'Game::Asset::PerlModule',
        %$index,
    };

    my ($entries, $entries_by_shortname) = $class->_build_entries( $zip,
        $args->{mappings} );
    $args->{entries} = $entries;
    $args->{'_entries_by_shortname'} = $entries_by_shortname;

    return $args;
}

sub _read_zip
{
    my ($class, $file) = @_;

    my $zip = Archive::Zip->new;
    my $read_result = $zip->read( $file );
    if( $read_result == AZ_STREAM_END ) {
        die "Hit end of stream unexpectedly in '$file'\n";
    }
    elsif( $read_result == AZ_ERROR ) {
        die "Generic error while reading '$file'\n";
    }
    elsif( $read_result == AZ_FORMAT_ERROR ) {
        die "Formatting error while reading '$file'\n";
    }
    elsif( $read_result == AZ_IO_ERROR ) {
        die "IO error while reading '$file'\n";
    }

    return $zip;
}

sub _read_index
{
    my ($class, $zip, $file) = @_;
    my $index_contents = $zip->contents( 'index.yml' );
    die "Could not find index.yml in '$file'\n" unless $index_contents;

    my $index = YAML::Load( $index_contents );
    return $index;
}

sub _build_entries
{
    my ($class, $zip, $mappings) = @_;
    my %mappings = %$mappings;

    my (@entries, %entries_by_shortname);
    foreach my $member ($zip->memberNames) {
        next if $member eq 'index.yml'; # Ignore index
        my ($short_name, $ext) = $member =~ /\A (.*) \. (.*?) \z/x;
        die "Could not find mapping for '$ext'\n"
            if ! exists $mappings{$ext};

        my $entry_class = $mappings{$ext};
        my $entry = $entry_class->new({
            name => $short_name,
        });
        push @entries, $entry;
        $entries_by_shortname{$short_name} = $entry;
    }

    return (\@entries, \%entries_by_shortname);
}



no Moose;
__PACKAGE__->meta->make_immutable;
1;
__END__

