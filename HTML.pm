package HTML;

use URI;
use URI::QueryParam;

sub New {
    my $ClassName = shift;
    my $Self      = shift;
    bless $Self, $ClassName;
    return $Self;
}

sub Hash2Query {
    my ($Self, $Hash) = @_;
    my $URI = URI->new;
    $URI->query_form_hash($Hash);
    return $URI->query;
}

sub HyperLink {
    my ($Self, $Attr) = @_;
    return qq!<a href="?$Attr->{HREF}">$Attr->{Text}</a>\n!;
}

sub NodeLink {
    my ($Self, $Attr) = @_;
    my $Node;
    my $UpDownArrow;
    if (defined($Attr->{Parent})) {
        $Node = $Attr->{Parent};
        $UpDownArrow = '&uarr;';
    } elsif (defined($Attr->{Child})) {
        $Node = $Attr->{Child};
        $UpDownArrow = '&darr;';
    }
    my $HREF = $Self->Hash2Query({
        FilterSchema          => $Node->{schema},
        FilterTable           => $Node->{table},
        FilterColumn          => $Node->{column},
        FilterValue           => $Node->{value},
        ShowUniqueNamesForIDs => $Self->{Params}->{ShowUniqueNamesForIDs}
    });
    if ($Attr->{Type} eq 'TABLE') {
        return $Self->HyperLink({
            HREF  => $HREF,
            Text => ($Node->{schema} eq 'public' ? '' : $Node->{schema} . '.') . $Node->{table}
        });
    } elsif ($Attr->{Type} eq 'VALUE' && $Self->{Params}->{ShowUniqueNamesForIDs} eq '1' && defined($Node->{label})) {
        return $Self->HyperLink({
            HREF  => $HREF,
            Text => $Node->{label}
        });
    }
    return $Self->HyperLink({
        HREF => $HREF,
        Text => $UpDownArrow . $Node->{value}
    });
}

sub Select {
    my ($Self, $Attr) = @_;
    my $HTML = qq!
        <select name="$Attr->{Name}" ! . ($Attr->{OnChangeSubmit} ? qq! onchange="document.getElementById('$Self->{FormID}').submit();"! : '') . qq!>
            <option value="$Attr->{DefaultValue}">$Attr->{DefaultText}</option>
    !;
    foreach my $Value (@{$Attr->{Options}}) {
        if ($Attr->{SelectedValue} eq $Value) {
            $HTML .= qq!<option selected="selected">$Value</option>\n!;
        } else {
            $HTML .= qq!<option>$Value</option>\n!;
        }
    }
    $HTML .= qq!</select>\n!;
    return $HTML;
}

sub Input {
    my ($Self, $Attr) = @_;
    my $HTML = '';

    my $Dec;
    my $Inc;
    if (defined($Attr->{Increment}) && $Attr->{Value} =~ m/^\d+$/) {
        $Dec = ($Attr->{Value} - $Attr->{Increment});
        if (defined($Attr->{Min}) && $Dec < $Attr->{Min}) {
            $Dec = undef;
        }
        $Inc = ($Attr->{Value} + $Attr->{Increment});
        if (defined($Attr->{Max}) && $Inc > $Attr->{Max}) {
            $Inc = undef;
        }
    }
    if (defined($Dec)) {
        $HTML .= qq!<input type="button" onClick="document.getElementById('$Attr->{Name}').value = '$Dec'; document.getElementById('$Self->{FormID}').submit();" value="$Dec"/>\n!;
    }
    $HTML .= qq!<input id="$Attr->{Name}" name="$Attr->{Name}" value="$Attr->{Value}"/>\n!;
    if (defined($Inc)) {
        $HTML .= qq!<input type="button" onClick="document.getElementById('$Attr->{Name}').value = '$Inc'; document.getElementById('$Self->{FormID}').submit();" value="$Inc"/>\n!;
    }
    return $HTML;
}

sub Table {
    my ($Self, $Rows) = @_;
    my $HTML = '';
    $HTML .= qq!<div class="table">\n!;
    my $HeaderRow = shift @$Rows;
    use Data::Dumper;
    print Dumper $HeaderRow;
    $HTML .= $Self->RowHeader(join('',@$HeaderRow));
    foreach my $Row (@$Rows) {
        $HTML .= $Self->Row(join('',@$Row));
    }
    $HTML .= qq!</div>\n!;
    return $HTML;
}

sub Row {
    my ($Self, $InnerHTML) = @_;
    return qq!<div class="row">$InnerHTML</div>\n!;
}

sub RowHeader {
    my ($Self, $InnerHTML) = @_;
    return qq!<div class="row header blue">$InnerHTML</div>\n!;
}

sub Cell {
    my ($Self, $Attr, $Classes) = @_;
    my $Column   = $Attr->{Column};
    my $Value    = $Attr->{Value};
    my $Classes  = $Attr->{Classes};
    push @$Classes, 'cell';
    my $HTML = '';
    if ($Self->{Params}->{FilterColumn} eq $Column
    &&  $Self->{Params}->{FilterValue}  eq $Value) {
        push @$Classes, 'blink_me';
    }
    $HTML .= qq!<div class="! . join(' ',@$Classes) . qq!">$Value</div>\n!;
    return $HTML;
}

sub Collapse {
    my ($Self, $Attr) = @_;
    my $ID = ++$Self->{CollapseCellID};
    my $HTML = '';
    $HTML .= qq!<label class="collapse link" for="cell-$ID">$Attr->{Label}</label>\n!;
    $HTML .= qq!<input id="cell-$ID" type="checkbox" checked/>\n!;
    $HTML .= qq!<div>\n$Attr->{InnerHTML}\n</div>\n!;
    return $HTML;
}

sub TextCell {
    my ($Self, $Attr) = @_;
    my $Text = $Attr->{Value};
    my $Classes = [];
    if (!defined($Text)) {
        push @$Classes, 'null';
        $Text = 'NULL';
    } elsif (length($Text) > 80) {
        $Text =~ s!^(.{40}).*?(.{40})$!$1...$2!;
        push @$Classes, 'truncated';
    }
    return $Self->Cell({Column => $Attr->{Column}, Value => $Text, Classes => $Classes});
}

sub Cells {
    my ($Self, $Values) = @_;
    my $Cells = [];
    foreach my $Value (@$Values) {
        push @$Cells, $Self->Cell({Value => $Value});
    }
    return $Cells;
}

sub Submit {
    my ($Self, $Attr) = @_;
    return qq!<input type="submit" value="$Attr->{Value}"/>\n!;
}

sub Body {
    my ($Self, $InnerHTML) = @_;
    return qq!<body translate="no">$InnerHTML</form>\n!;
}

sub Head {
    my ($Self, $Attr) = @_;
    return qq!
        <head>
            <meta charset="UTF-8" />
            <meta http-equiv="Content-language" content="en">
            <style type="text/css">$Attr->{CSS}</style>
        </head>
    !;
}

sub HTML {
    my ($Self, $InnerHTML) = @_;
    return qq!<html>\n$InnerHTML\n</html>!;
}

sub Form {
    my ($Self, $InnerHTML) = @_;
    return qq!<form id="$Self->{FormID}">\n$InnerHTML\n</form>\n!;
}

sub ResetButton {
    my ($Self, $Attr) = @_;
    my $HTML = '';
    $HTML .= qq!<input type="button" onClick="document.getElementById('$Attr->{Name}').value = ''; document.getElementById('$Self->{FormID}').submit();" value="$Attr->{Text}"/>\n!;
}

sub ToggleButton {
    my ($Self, $Attr) = @_;
    my $HTML = '';
    my $CurValue   = $Self->{Params}->{$Attr->{Name}} || '0';
    my $InvValue   = $CurValue eq '1' ? '0' : '1';
    my $ButtonText = $CurValue eq '1' ? $Attr->{OnButton} : $Attr->{OffButton};
    $HTML .= qq!<input type="hidden" name="$Attr->{Name}" id="$Attr->{Name}" value="$CurValue" />\n!;
    $HTML .= qq!<input type="button" onClick="document.getElementById('$Attr->{Name}').value = '$InvValue'; document.getElementById('$Self->{FormID}').submit();" value="$ButtonText"/>\n!;
    return $HTML;
}

sub Menu {
    my ($Self, $Elements) = @_;
    my $HTML = '';
    $HTML .= qq!<div class="menu">\n!;
    foreach my $InnerHTML (@$Elements) {
        $HTML .= qq!<div class="cell">\n$InnerHTML\n</div>\n!;
    }
    $HTML .= qq!</div>\n!;
    return $HTML;
}

1;