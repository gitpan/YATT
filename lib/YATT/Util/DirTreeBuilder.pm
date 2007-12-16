# -*- mode: perl; coding: utf-8 -*-
package YATT::Util::DirTreeBuilder;
use strict;
use warnings FATAL => qw(all);

use base qw(YATT::Class::Configurable Exporter);
our @EXPORT_OK = qw(tmpbuilder);

use fields qw(cf_DIR cf_TESTNO cf_AUTO_REMOVE);
use overload '&{}' => 'as_sub';
use File::Remove qw(remove);

sub MY () {__PACKAGE__}

sub tmpbuilder {
  my ($tmpdir) = @_;
  unless (-d $tmpdir) {
    mkdir $tmpdir or die "Can't mkdir $tmpdir: $!";
  }
  MY->new(DIR => $tmpdir, TESTNO => 0
	  , AUTO_REMOVE => !$ENV{DEBUG_TMP});
}

sub DESTROY {
  my MY $self = shift;
  remove \1, $self->{cf_DIR} if $self->{cf_AUTO_REMOVE};
}

sub as_sub {
  my MY $self = shift;
  my $basedir = $self->{cf_DIR} . '/t' . ++$self->{cf_TESTNO};
  unless (-d $basedir) {
    mkdir $basedir or die "Can't mkdir $basedir! $!";
  }
  sub {
    $self->build($basedir, @_);
    if (wantarray) {
      ($basedir, sub {
	 $self->build($basedir, [FILE => @_])
       });
    } else {
      $basedir;
    }
  }
}

sub build {
  my ($self, $basedir, @action) = @_;
  foreach my $action (@action) {
    next unless ref $action eq 'ARRAY';
    my $sub = $self->can("build_" . $action->[0])
      or die "Invalid builder spec: $action->[0]";
    $sub->($self, $basedir, @{$action}[1 .. $#$action]);
  }
}

sub build_DIR {
  my ($self, $basedir, $name, @action) = @_;
  my $dir = "$basedir/$name";
  unless (-d $dir) {
    mkdir($dir) or die "Can't mkdir $dir: $!";
  }
  $self->build($dir, @action);
}

sub build_FILE {
  my ($self, $basedir, $name, @body) = @_;
  my $fn = "$basedir/$name";
  open(my $out, '>', $fn), "file  $fn" or die "Can't create $fn: $!";
  print $out @body;
}

1;
