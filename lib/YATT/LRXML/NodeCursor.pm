package YATT::LRXML::NodeCursor; # Location, Zipper?
use strict;
use warnings FATAL => qw(all);

use base qw(YATT::Class::Configurable);
use YATT::Fields qw(^tree cf_metainfo cf_path);
sub Path () {'YATT::LRXML::NodeCursor::Path'}

use YATT::Util::Symbol;
use YATT::LRXML::Node qw(stringify_node);

# XXX: Configurable �� init �� clone �Υץ�ȥ����Ĥäơ�
# fields ����Ȥ˰�¸���뤫�顢��Ф�����

BEGIN {
  package YATT::LRXML::NodeCursor::Path;
  use base qw(YATT::Class::ArrayScanner);
  use YATT::Fields qw(cf_path);

  sub init {
    my ($self, $array, $path, $index0) = splice @_, 0, 4;
    $self->SUPER::init(array => $array
		       , index => ($index0 || 0)
		       + YATT::LRXML::Node::_BODY
		       , path => $path, @_);
  }

  sub parent {
    my MY $path = shift; $path->{cf_path}
  }
}

sub initargs {qw(tree)}

sub new_path {
  my MY $self = shift;
  $self->Path->new($self->{tree}, shift);
}

sub clone {
  (my MY $self, my ($path)) = @_;
  # XXX: ¾�Υѥ�᡼����? �äˡ��Ѿ����­�����ѥ�᡼����
  ref($self)->new($self->{tree}
		  , metainfo => $self->{cf_metainfo}
		  , path => ($path || $self->{cf_path}));
}

sub open {
  my MY $self = shift;
  my $obj;
  unless (defined (my Path $path = $self->{cf_path})) {
    $self->clone($self->new_path);
  } elsif (not defined ($obj = $path->{cf_array}->[$path->{cf_index}])
	   or ref $obj ne 'ARRAY') {
    $obj;
  } else {
    # ������ clone ���ɤ��Τ�����?
    $self->clone($self->Path->new($obj, $path));
  }
}

# cursor ���ΤǤϤʤ���path �������ߤ����Ȥ��Τ���ˡ�
# �� open �򥫥����ޥ��������������Ѥ��롣
sub open_path {
  my MY $self = shift;
  unless (defined (my Path $path = $self->{cf_path})) {
    $self->new_path;
  } else {
    my $obj = $path->{cf_array}->[$path->{cf_index}];
    die "Not an object!" unless defined $obj && ref $obj eq 'ARRAY';
    $self->Path->new($obj, $path);
  }
}

sub can_open {
  my MY $self = shift;
  my Path $path = $self->{cf_path};
  my $obj = $path->{cf_array}->[$path->{cf_index}];
  defined $obj && ref $obj eq 'ARRAY';
}

sub close {
  my MY $self = shift;
  if (my Path $parent = $self->{cf_path}->parent) {
    $parent->{cf_index}++;
    $self->clone($parent);
  } else {
    return
  }
}

sub can_close {
  my MY $self = shift;
  defined $self->{cf_path};
}

BEGIN {
  my @delegate_to_path =
    qw(read
       current
       next
       prev
     );
  foreach my $meth (@delegate_to_path) {
    *{globref(__PACKAGE__, $meth)} = sub {
      my MY $self = shift;
      return unless defined $self->{cf_path};
      $self->{cf_path}->$meth(@_);
    };
  }

  my @delegate_and_self = qw(go_next);
  foreach my $meth (@delegate_and_self) {
    *{globref(__PACKAGE__, $meth)} = sub {
      my MY $self = shift;
      return unless defined $self->{cf_path};
      $self->{cf_path}->$meth(@_);
      $self;
    };
  }

  foreach my $meth (grep {/^(node|is)_/} YATT::LRXML::Node->exports) {
    my $for_text = do {no strict 'refs'; \&{"text_$meth"}};
    my $sub = YATT::LRXML::Node->can($meth);
    *{globref(__PACKAGE__, $meth)} = sub {
      my MY $cursor = shift;
      return unless $cursor->readable;
      if (ref(my $value = $cursor->current)) {
	$sub->($value, @_);
      } else {
	$for_text->($value, @_);
      }
    };
  }
}

sub readable {
  my MY $self = shift;
  defined $self->{cf_path} && $self->{cf_path}->readable;
}

# value, size �����Ρ�
sub value {
  my MY $self = shift;
  unless (defined $self->{cf_path}) {
    $self->{tree}
  } else {
    $self->{cf_path}->value;
  }
}

sub size {
  my MY $self = shift;
  unless (defined (my Path $path = $self->{cf_path})) {
    YATT::LRXML::Node::node_size($self->{tree});
  } elsif (not defined (my $obj = $path->{cf_array}->[$path->{cf_index}])) {
    0
  } elsif (ref $obj) {
    YATT::LRXML::Node::node_size($obj);
  } else {
    1;
  }
}

sub node_is_beginning {
  my MY $self = shift;
  my Path $path = $self->{cf_path} or return;
  defined $path->{cf_index} or return;
  $path->{cf_index} == YATT::LRXML::Node::_BODY;
}

sub node_is_end {
  my MY $self = shift;
  my Path $path = $self->{cf_path} or return;
  defined $path->{cf_index} or return;
  $path->{cf_index} == $#{$path->{cf_array}};
}

sub stringify {
  my MY $self = shift;
  unless (defined $self->{cf_path}) {
    stringify_node($self->{tree});
  } elsif (ref (my $value = $self->current)) {
    stringify_node($value);
  } else {
    $value;
  }
}

sub path_list {
  my MY $self = shift;
  my @path;
  if (my Path $path = $self->{cf_path}) {
  # XXX: �졢����Ƥ뤸��󡢤ȡ�������?
    do {
      unshift @path, $path->{cf_index} - YATT::LRXML::Node::_BODY;
      $path = $path->{cf_path};
    } while $path;
  }
  wantarray ? @path : join ", ", @path;
}

sub text_is_attribute { 0 }
sub text_is_primary_attribute { 0 }
sub text_is_quoted_by_element { 0 }
sub text_node_size { 1 }
sub text_node_type { YATT::LRXML::Node::TEXT_TYPE }
sub text_node_body { shift }
sub text_node_type_name { 'text' }
sub text_node_name { undef }

1;
