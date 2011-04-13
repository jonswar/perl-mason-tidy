package Mason::Tidy::Compilation;
use Mason::Tidy::Moose;

# Valid Perl identifier
my $identifier = qr/[[:alpha:]_]\w*/;

# Passed attributes
has 'source'      => ( required => 1 );
has 'tidy_object' => ( required => 1 );

# Derived attributes
has 'named_block_regex'   => ( lazy_build => 1, init_arg => undef );
has 'unnamed_block_regex' => ( lazy_build => 1, init_arg => undef );

#
# BUILD
#

method _build_named_block_regex () {
    my $re = join '|', @{ $self->named_block_types };
    return qr/$re/i;
}

method _build_unnamed_block_regex () {
    my $re = join '|', @{ $self->unnamed_block_types };
    return qr/$re/i;
}

method named_block_types () {
    return [qw(after augment around before filter method override)];
}

method unnamed_block_types () {
    return [qw(args class doc flags init perl shared text)];
}

method handle_block ()          { $self->handle_default(@_) }
method handle_component_call () { $self->handle_default(@_) }
method handle_perl_line ()      { $self->handle_default(@_) }
method handle_plain_text ()     { $self->handle_default(@_) }
method handle_substitution ()   { $self->handle_default(@_) }

method parse () {
    while (1) {
        $self->_match_end            && last;
        $self->_match_unnamed_block  && next;
        $self->_match_named_block    && next;
        $self->_match_unknown_block  && next;
        $self->_match_substitution   && next;
        $self->_match_component_call && next;
        $self->_match_perl_line      && next;
        $self->_match_plain_text     && next;

        $self->_throw_syntax_error(
            "could not parse next element at position " . pos( $self->{source} ) );
    }
}

method _match_apply_filter () {
    my $pos = pos( $self->{source} );

    # Match <% ... { %>
    if ( $self->{source} =~ /\G((\n)? <% (.+?) (\s*\{\s*) %>(\n)?)/xcgs ) {
        my ( $whole, $preceding_newline, $filter_expr ) = ( $1, $2, $3 );

        # and make sure we didn't go through a %>
        if ( $filter_expr !~ /%>/ ) {
            $self->handle_apply_filter( $pos, length($whole) );
            return 1;
        }
        else {
            pos( $self->{source} ) = $pos;
        }
    }
    return 0;
}

method _match_apply_filter_end () {
    if (   $self->{current_method}->{type} eq 'apply_filter'
        && $self->{source} =~ /\G (?: (?: <% [ \t]* \} [ \t]* %> ) | (?: <\/%> ) ) (\n?\n?)/gcx )
    {
        $self->{end_parse} = pos( $self->{source} );
        return 1;
    }
    return 0;
}

method _match_block ($block_regex, $named) {
    my $pos   = pos( $self->{source} );
    my $regex = qr/
               \G((\n?)
               <% ($block_regex)
               (?: \s+ ([^\s\(>]+) ([^>]*) )?
               >)
    /x;
    if ( $self->{source} =~ /$regex/gcs ) {
        my ( $tag, $block_type ) = ( $1, $3 );
        my ($block_contents) = $self->_match_block_end($block_type);
        my $length = length($tag) + length($block_contents);
        $self->handle_block( $pos, $length, $block_type );
        return 1;
    }
    return 0;
}

method _match_block_end ($block_type) {
    my $re = qr,\G((.*?)</%\Q$block_type\E>),is;
    if ( $self->{source} =~ /$re/gc ) {
        return $1;
    }
    else {
        $self->_throw_syntax_error("<%$block_type> without matching </%$block_type>");
    }
}

method _match_component_call () {
    my $pos = pos( $self->{source} );
    if ( $self->{source} =~ /\G(<&(?!\|))/gcs ) {
        my $begin_tag = $1;
        if ( $self->{source} =~ /\G((.*?)&>)/gcs ) {
            $self->handle_component_call( $pos, length($1) + length($begin_tag) );
            return 1;
        }
        else {
            $self->_throw_syntax_error("'<&' without matching '&>'");
        }
    }
}

method _match_end () {
    if ( $self->{source} =~ /(\G\z)/gcs ) {
        return defined $1 && length $1 ? $1 : 1;
    }
    return 0;
}

method _match_named_block () {
    $self->_match_block( $self->named_block_regex, 1 );
}

method _match_perl_line () {
    my $pos = pos( $self->{source} );
    if ( $self->{source} =~ /\G((?<=^)(%%?)([^\n]*)(?:\n|\z))/gcm ) {
        $self->handle_perl_line( $pos, length($1) - 1 );
        return 1;
    }
    return 0;
}

method _match_plain_text () {
    my $pos = pos( $self->{source} );

    # Most of these terminator patterns actually belong to the next
    # lexeme in the source, so we use a lookahead if we don't want to
    # consume them.  We use a lookbehind when we want to consume
    # something in the matched text, like the newline before a '%'.

    if (
        $self->{source} =~ m{
                                \G
                                (
                                (.*?)         # anything, followed by:
                                (
                                 (?<=\n)(?=%) # an eval line - consume the \n
                                 |
                                 (?=<%\s)     # a substitution tag
                                 |
                                 (?=[%&]>)    # an end substitution or component call
                                 |
                                 (?=</?[%&])  # a block or call start or end
                                              # - don't consume
                                 |
                                 \\\n         # an escaped newline  - throw away
                                 |
                                 \z           # end of string
                                )
                                )
                               }xcgs
      )
    {
        $self->handle_plain_text( $pos, length($1) );
        return 1;
    }

    return 0;
}

method _match_substitution () {
    my $pos = pos( $self->{source} );
    return 0 unless $self->{source} =~ /\G<%/gcs;

    if (
        $self->{source} =~ m{
           \G
           (
           (\s*)                # Initial whitespace
           (.+?)                # Substitution body ($1)
           (
            \s*
            (?<!\|)             # Not preceded by a '|'
            \|                  # A '|'
            \s*
            (                   # (Start $3)
             $identifier            # A filter name
             (?:\s*,\s*$identifier)*  # More filter names, with comma separators
            )
           )?
           (\s*)                # Final whitespace
           %>                   # Closing tag
           )
          }xcigs
      )
    {
        $self->handle_substitution( $pos, length($1) + 2 );
        return 1;
    }
    else {
        $self->_throw_syntax_error("'<%' without matching '%>'");
    }
}

method _match_unknown_block () {
    if ( $self->{source} =~ /\G(?:\n?)<%([A-Za-z_]+)>/gc ) {
        $self->_throw_syntax_error("unknown block '<%$1>'");
    }
}

method _match_unnamed_block () {
    $self->_match_block( $self->unnamed_block_regex, 0 );
}

method _match_bad_close_tag () {
    if ( my ($end_tag) = ( $self->{source} =~ /\G\s*(%>|&>)/gc ) ) {
        ( my $begin_tag = reverse($end_tag) ) =~ s/>/</;
        $self->_throw_syntax_error("'$end_tag' without matching '$begin_tag'");
    }
}

method _throw_syntax_error ($msg) {
    die $msg;
}

method unique_string () {
    return $self->tidy_object->unique_string;
}

1;
