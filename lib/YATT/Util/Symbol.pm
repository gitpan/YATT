# -*- mode: perl; coding: utf-8 -*-
package YATT::Util::Symbol;
use base qw(Exporter);
use strict;
BEGIN {
  our @EXPORT_OK = qw(class symtab globref globelem
		      glob_default glob_init findname
		      gather_classvars
		      delete_package
		      pkg_exists pkg_ensure_main pkg_split
		    );
  our @EXPORT    = @EXPORT_OK;
}

use YATT::Util qw(numeric);

sub class {
  ref $_[0] || $_[0]
}

# Do not use this as method. Use as symtab($obj),
# or it will return your *base* class!
sub symtab {
  no strict 'refs';
  my $class = class($_[0]);
  $class =~ s/:*$/::/;
  *{$class}{HASH};
}

sub globref {
  my ($thing, $name) = @_;
  no strict 'refs';
  \*{class($thing) . "::$name"};
}

sub globelem {
  no strict 'refs';
  *{$_[0]}{$_[1]}
}

sub glob_default {
  no strict 'refs';
  my $type = ref $_[1];
  *{$_[0]}{$type} || do {
    *{*{$_[0]} = $_[1]}{$type}
  };
}

sub glob_init {
  my ($sym, $type, $sub) = @_;
  no strict 'refs';
  *{$sym}{$type} || do {
    *{*$sym = $sub->()}{$type}
  }
}

# stolen/modified from Attribute::Handlers
{
  my %symcache;
  sub findname {
    my ($pkg, $ref, $type) = @_;
    return $symcache{$pkg,$ref} if $symcache{$pkg,$ref};
    $type ||= ref $ref;
    my $symtab = symtab($pkg);
    foreach my $name (keys %$symtab) {
      my $sym = $symtab->{$name};
      return $symcache{$pkg,$ref} = $name
	if globelem($sym, $type) && globelem($sym, $type) == $ref;
    }
  }
}

sub gather_classvars {
  my ($baseClass, $leafClass, $arrayName) = @_;
  my $ary = *{globref($leafClass, $arrayName)}{ARRAY};
  my @result = ([$leafClass, $ary ? @$ary : ()]);
  if ($leafClass ne $baseClass) {
    my $isa = *{globref($leafClass, 'ISA')}{ARRAY};
    foreach my $super ($isa ? @$isa : ()) {
      next unless UNIVERSAL::isa($super, $baseClass);
      push @result, gather_classvars($baseClass, $super, $arrayName);
    }
  }
  @result;
}

#

sub pkg_exists {
  my ($stem, $leaf) = pkg_split(@_);
  my $stem_symtab = symtab($stem);
  defined $stem_symtab && exists $stem_symtab->{$leaf};
}

sub pkg_split {
  $_[0] =~ s{:*$}{::};
  my ($stem, $leaf) = $_[0] =~ m/(.*::)(\w+::)$/
    or die "Can't split package: $_[0]";
  ($stem, $leaf);
}

sub pkg_ensure_main {
  my ($pkg) = @_;
  unless ($pkg =~ /^main::.*::$/) {
    $pkg = "main$pkg"       if      $pkg =~ /^::/;
    $pkg = "main::$pkg"     unless  $pkg =~ /^main::/;
    $pkg .= '::'            unless  $pkg =~ /::$/;
  }
  $pkg;
}

# Stolen from Symbol.pm
sub delete_package ($;$) {
  my ($pkg, $debug) = (shift, numeric(shift));
  my ($stem, $leaf) = pkg_split($pkg);
  my $stem_symtab = symtab($stem);
  unless (defined $stem_symtab and exists $stem_symtab->{$leaf}) {
    print STDERR "package is already empty: $pkg \[$stem $leaf]\n" if $debug;
    return;
  }

  # free all the symbols in the package
  my $leaf_symtab = *{$stem_symtab->{$leaf}}{HASH};
  foreach my $name (keys %$leaf_symtab) {
    print STDERR "deleting $pkg$name\n" if $debug >= 2;
    my $sym = delete $leaf_symtab->{$name};
    next unless defined $sym and ref $sym eq 'GLOB'; # XXX: but why?
    undef *$sym;
  }

  # delete the symbol table
  %$leaf_symtab = ();
  delete $stem_symtab->{$leaf};
}

sub let_in {
  my ($pack, $obj, $binding) = splice @_, 0, 3;
  my ($k, $v) = splice @$binding, 0, 2;
  local *{globref($pack, $k)} = $v;
  if (@$binding) {
    let_in($pack, $obj, $binding, @_);
  } else {
    my ($method) = shift;
    $obj->$method(@_);
  }
}

1;
