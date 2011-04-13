package Mason::Tidy::Compilation::PlainText;
use Mason::Tidy::Moose;
use HTML::PullParser;
extends 'Mason::Tidy::Compilation';

method handle_default ($pos, $length) {
    $pos ||= 0;
    $self->{untidied_html} .= "\n";
}

method handle_plain_text ($pos, $length) {
    $pos ||= 0;
    my $text = substr( $self->{source}, $pos, $length );
    my $marker = sprintf( "<!--%s-->", $self->unique_string );
    my $nl;
    if ( $pos > 0 && substr( $self->{source}, $pos - 1, 1 ) eq "\n" ) {
        $text = "\n$text";
        $nl   = 1;
    }
    my $marked_html = $marker . $text . $marker;
    $self->{untidied_html} .= $marked_html;
    push( @{ $self->{to_replace} }, [ $marker, $pos, $length, $nl ] );
}

method replace_all () {
    my $adjust = 0;
    foreach my $repl ( @{ $self->{to_replace} } ) {
        my ( $marker, $pos, $length, $nl ) = @$repl;
        my ($tidied) = ( $self->{tidied_html} =~ /$marker(.*)$marker/s )
          or die "could not find code delimited by '$marker': " . $self->{tidied_html};
        $tidied =~ s/^\n// if $nl;
        my $next = substr( $self->{source}, $pos + $adjust + $length, 3 );
        $tidied =~ s/[ \t]+$// unless $next eq '<% ' || $next =~ /<&/;
        substr( $self->{source}, $pos + $adjust, $length ) = $tidied;
        $adjust += ( length($tidied) - $length );
    }
}

method transform () {
    $self->parse;
    $self->{tidied_html} = $self->tidy_html( $self->{untidied_html} );
    $self->replace_all;
}

method tidy_html ($source) {
    my $p = HTML::PullParser->new(
        doc             => $source,
        start           => '"S", text, tagname',
        end             => '"E", text, tagname',
        default         => '"O", text',
        ignore_elements => [qw(script style)],
    ) || die "Can't open: $!";
    my $lineno = 0;
    my @deltas;

    my @tagname_stack;
    while ( my $token = $p->get_token ) {
        my ( $type, $text, $tagname ) = @$token;
        if ( $type eq 'S' ) {
            $deltas[$lineno]++;
            push( @tagname_stack, $tagname );
        }
        if ( $type eq 'E' ) {
            while ( my $popped_tagname = pop(@tagname_stack) ) {
                $deltas[$lineno]--;
                last if $popped_tagname eq $tagname;
            }
        }
        $lineno += ( $text =~ tr/\n// );
    }

    my $level  = 0;
    my $result = '';
    my @lines  = split( "\n", $source );

    for ( my $lineno = 0 ; $lineno < @lines ; $lineno++ ) {
        my $delta = $deltas[$lineno] || 0;
        $level += $delta if $delta < 0;
        $level = 0 if $level < 0;
        $result .= scalar( '  ' x $level ) . $lines[$lineno] . "\n";
        $level += $delta if $delta > 0;
    }
    return $result;
}

1;
