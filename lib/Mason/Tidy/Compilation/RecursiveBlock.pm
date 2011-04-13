package Mason::Tidy::Compilation::RecursiveBlock;
use Mason::Tidy::Moose;
use Perl::Tidy qw();
extends 'Mason::Tidy::Compilation';

method handle_default () { }

method handle_block ($pos, $length, $block_type) {
    if ( $block_type =~ /^(?:after|augment|around|before|filter|method|override)/ ) {

        # Get what's inside the block tags
        #
        my $untidied = substr( $self->{source}, $pos, $length );
        $untidied =~ s/^<%[^>]+>//;
        $pos += ( $length - length($untidied) );
        $untidied =~ s/<\/%[^>]+>$//;
        $length = length($untidied);
        push( @{ $self->{to_replace} }, [ $pos, $length, $untidied ] );
    }
}

method replace_all () {
    my $adjust = 0;
    foreach my $repl ( @{ $self->{to_replace} } ) {
        my ( $pos, $length, $untidied ) = @$repl;
        my $tidied = $self->tidy_object->tidy($untidied);
        for ($tidied) { s/^\s+//; s/\s+$// }
        $tidied = "\n$tidied\n";
        substr( $self->{source}, $pos + $adjust, $length ) = $tidied;
        $adjust += ( length($tidied) - $length );
    }
}

method transform () {
    $self->parse;
    $self->replace_all;
}

1;
