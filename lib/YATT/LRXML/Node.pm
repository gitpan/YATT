package YATT::LRXML::Node;
# Media か？
# To cooperate with JSON easily, Nodes should not rely on OO style.

use strict;
use warnings FATAL => qw(all);
use YATT::Util::Symbol;
use YATT::Util;

use base qw(Exporter);
our (@EXPORT_OK, @EXPORT);
BEGIN {
  @EXPORT_OK = qw(stringify_node
		  create_node
		  create_attlist
		  node_size
		  node_type_name
		  node_name
		  node_nsname
		  node_path
		  node_user_data
		  node_user_data_by
		  is_attribute
		  is_primary_attribute
		  is_quoted_by_element

		  quoted_by_element
		);
  @EXPORT = @EXPORT_OK;
}

sub exports { @EXPORT_OK }

sub MY () {__PACKAGE__}

our @NODE_MEMBERS; BEGIN {@NODE_MEMBERS = qw(TYPE FLAG USER_SLOT
					     RAW_NAME BODY)}
use YATT::Util::Enum -prefix => '_', @NODE_MEMBERS;

BEGIN {
  foreach my $name (@NODE_MEMBERS) {
    my $offset = MY->can("_$name")->();
    my $func = "node_".lc($name);
    *{globref(MY, $func)} = sub {
      shift->[$offset]
    };
    push @EXPORT_OK, $func;
    push @EXPORT, $func;
  }
}

our @NODE_TYPES;
our %NODE_TYPES;
our @NODE_FORMAT;

BEGIN {
  my @desc = ([text => '%s'] # May not be used.
	      , [comment => '<!--#%2$s' . '%1$s-->']
	      , [decl_comment => '--%1$s--']
	      , [pi      => '<?%2$s'    . '%1$s?>' ]
	      , [entity  => '&%2$s'     . '%1$s;'  ]
	      , [decl_entity  => '%%%2$s'     . '%1$s;'  ]
	      , [root    => \&stringify_root]
	      , [element => \&stringify_element]
	      , [attribute => \&stringify_attribute]
	      , [declarator => \&stringify_declarator]
	      , [html => \&stringify_element]
	      , [unknown => \&stringify_unknown]
	      );
  $NODE_TYPES{$_->[0]} = keys %NODE_TYPES for @desc;
  @NODE_TYPES  = map {$_->[0]} @desc;
  @NODE_FORMAT = map {$_->[1]} @desc;
}

BEGIN {
  my @type_enum = map {uc($_) . '_TYPE'} @NODE_TYPES;
  require YATT::Util::Enum;
  import YATT::Util::Enum @type_enum;
  push @EXPORT_OK, @type_enum;
  push @EXPORT, @type_enum;
}

# ATTRIBUTE の FLAG の意味は、↓これと &quoted_by_element が決める。
our @QUOTE_CHAR; BEGIN {@QUOTE_CHAR = ("", '\'', "\"", [qw([ ])])}
# XXX: ↓ 役割は減る予定。
our @QUOTE_TYPES; BEGIN {@QUOTE_TYPES = (1, 2, 0)}

sub new {
  my $pack = shift;
  bless $pack->create_node(@_), $pack;
}

# $pack->create_node($typeName, $nodeName, $nodeBody)
# $pack->create_node([$typeName, $flag], [@nodePath], @nodeBody)

sub create_node {
  my ($pack, $type, $name) = splice @_, 0, 3;
  my ($typename, $flag) = ref $type ? @$type : $type;
  $flag = 0 unless defined $flag;
  my $typeid = $NODE_TYPES{$typename};
  die "Unknown type: $typename" unless defined $typeid;
  [$typeid, $flag, undef, $name, @_];
}

sub node_body_starting () { _BODY }

sub node_size {
  my $node = shift;
  @$node - _BODY;
}

sub node_type_name {
  $NODE_TYPES[shift->[_TYPE]];
}

sub is_attribute {
  $_[0]->[_TYPE] == ATTRIBUTE_TYPE;
}

sub is_primary_attribute {
  $_[0]->[_TYPE] == ATTRIBUTE_TYPE
    && $_[0]->[_FLAG] < @QUOTE_CHAR;
}

sub stringify_node {
  my ($node) = shift;
  my $type = $node->[_TYPE];
  if (@NODE_FORMAT <= $type) {
    die "Unknown type: $type";
  }
  if (ref(my $fmt = $NODE_FORMAT[$type])) {
    $fmt->($node, @_);
  } else {
    sprintf $fmt, $node->[_BODY], node_nsname($node, '');
  }
}

# node_path は name スロットを返す。wantarray 対応。

sub node_path {
  my ($node, $first, $sep) = @_;
  my $raw;
  unless (defined ($raw = $node->[_RAW_NAME]) and ref $raw) {
    # undef かつ wantarray は只の return に分離した方が良いかも？
    $raw;
  } else {
    my @names = @$raw[($first || 0) .. $#$raw];
    wantarray ? @names : join(($sep || ":")
			      , map {defined $_ ? $_ : ''} @names);
  }
}

# node_nsname は namespace 込みのパスを返す。

sub node_nsname {
  my ($node, $sep) = @_;
  scalar node_path($node, 0, $sep);
}

# node_name は namespace を除いたパスを返す。
# yatt:else なら else が返る。

sub node_name {
  my ($node, $sep) = @_;
  node_path($node, 1, $sep);
}

sub node_user_data {
  my ($node) = shift;
  if (@_) {
    $node->[_USER_SLOT] = shift;
  } else {
    $node->[_USER_SLOT];
  }
}

sub node_user_data_by {
  my ($node) = shift;
  my $slot = $node->[_USER_SLOT] ||= do {
    my ($obj, $meth) = splice @_, 0, 2;
    $obj->$meth(@_);
  };
  wantarray ? @$slot : $slot;
}

#----------------------------------------

sub stringify_element {
  my ($elem) = @_;
  stringify_as_tag($elem, node_nsname($elem), $elem->[_FLAG]);
}

sub stringify_declarator {
  my ($elem, $strip_ns) = @_;
  # XXX: 本物にせよ。
  my $tag = node_nsname($elem);
  my $attlist = stringify_each_by($elem, ' ', ' ', '', _BODY);
  "<!$tag$attlist>"
}

sub stringify_root {
  my ($elem) = @_;
    stringify_each_by($elem
		      , ''
		      , ''
		      , ''
		      , _BODY);
}

sub stringify_unknown {
  die 'unknown';
}

#----------------------------------------

sub stringify_as_tag {
  my ($node, $name, $is_ee) = @_;
  my $bodystart = node_beginning_of_body($node);
  my $tag = do {
    if (defined $name && is_attribute($node)) {
      ":$name";
    } else {
      $name;
    }
  };
  my $attlist = stringify_attlist($node, $bodystart);
  if ($is_ee) {
    stringify_each_by($node
		      , $tag ? qq(<$tag$attlist />) : ''
		      , ''
		      , ''
		      , $bodystart);
  } else {
    stringify_each_by($node
		      , $tag ? qq(<$tag$attlist>) : ''
		      , ''
		      , $tag ? qq(</$tag>) : ''
		      , $bodystart);
  }
}

sub stringify_attlist {
  my ($node) = shift;
  my $bodystart = shift || node_beginning_of_body($node);
  #  print "[[for @{[$node->get_name]}; <",
  return '' if defined $bodystart and _BODY == $bodystart
    or not defined $bodystart and $#$node < _BODY;
  stringify_each_by($node, ' ', ' ', '', _BODY
		    , (defined $bodystart ? ($bodystart - 1) : ()))
}

sub stringify_each_by {
  my ($node, $open, $sep, $close) = splice @_, 0, 4;
  $open ||= ''; $sep ||= ''; $close ||= '';
  my $from = @_ ? shift : _BODY;
  my $to = @_ ? shift : $#$node;
  my $result = $open;
  if (defined $from and defined $to) {
    $result .= join $sep, map {ref $_ ? stringify_node($_) : $_}
      @{$node}[$from .. $to];
  }
  $result .= $close if defined $close;
  $result;
}

sub node_beginning_of_body {
  my ($node) = @_;
  lsearch {
    not ref $_ or not is_attribute($_)
  } $node, _BODY;
}

#----------------------------------------

sub create_attlist {
  my ($parser) = shift;
  my @result;
  while (@_) {
    my ($name, @values) = splice @_, 0, 4;
    my $found = lsearch {defined} \@values;
    my ($subtype, $attname, @attbody) = do {
      unless (defined $found) {
	(undef, $name);
      } elsif (not defined $name and $found == 2
	      and $values[$found] =~ /^[\w\:\-\.]+$/) {
	# has single bareword. use it as name and keep value undef.
	(undef, $values[$found]);
      } else {
	# parse_entities can return ().
	($QUOTE_TYPES[$found], $name =>
	 $parser->parse_entities($values[$found]));
      }
    };
    push @result, [ATTRIBUTE_TYPE, $subtype, undef, $attname, @attbody];
  }
  @result;
}

sub stringify_attribute {
  my ($node) = @_;
  unless (defined $$node[_BODY]) {
    $$node[_RAW_NAME];
  } elsif ($$node[_FLAG] >= @QUOTE_CHAR) {
    stringify_as_tag($node
		     , node_nsname($node)
		     , $$node[_FLAG] - MY->quoted_by_element(0));
  } else {
    # attribute だけは、 _RAW_NAME を id 化しない。
    my $Q = $$node[_FLAG] ? @QUOTE_CHAR[$$node[_FLAG]] : "";
    if (ref $Q) {
      stringify_each_by($node
			, $Q->[0] . join_or_empty($$node[_RAW_NAME], ' ')
			, ' '
			, $Q->[1]
			, _BODY
		       );
    } else {
      stringify_each_by($node
			, join_or_empty($$node[_RAW_NAME], '=').$Q
			, ''
			, $Q
			, _BODY);
    }
  }
}

sub join_or_empty {
  my $str = '';
  foreach my $item (@_) {
    return '' unless defined $item;
    $str .= $item;
  }
  $str;
}

sub quoted_by_element {
  my ($pack, $is_ee) = @_;
  if ($is_ee) {
    1 + @QUOTE_CHAR;
  } else {
    scalar @QUOTE_CHAR; # 3 for now.
  }
}

sub is_quoted_by_element {
  my ($node) = @_;
  $node->[_FLAG] >= @QUOTE_CHAR;
}

sub is_empty_element {
  my ($node) = @_;
  $node->[_FLAG] == 1 + @QUOTE_CHAR;
}

1;
