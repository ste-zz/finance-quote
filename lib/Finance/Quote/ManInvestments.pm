#!/usr/bin/perl -w
#
#    Copyright (C) 1998, Dj Padzensky <djpadz@padz.net>
#    Copyright (C) 1998, 1999 Linas Vepstas <linas@linas.org>
#    Copyright (C) 2000, Yannick LE NY <y-le-ny@ifrance.com>
#    Copyright (C) 2000, Paul Fenwick <pjf@Acpan.org>
#    Copyright (C) 2000, Brent Neal <brentn@users.sourceforge.net>
#    Copyright (C) 2001, Leigh Wedding <leigh.wedding@telstra.com>
#    Copyright (C) 2003, Ian Dall <ian@beware.dropbear.id.au>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
#    02111-1307, USA
#
#
# This code derived from Padzensky's work on package Finance::YahooQuote,
# but extends its capabilites to additional data sources.
#
# This code was developed as part of GnuCash <http://www.gnucash.org/>

require 5.005;

use strict;

package Finance::Quote::ManInvestments;

use HTTP::Request::Common;
use LWP::UserAgent;
use HTML::TableExtract;

use vars qw/$MANINV_URL $VERSION/;

$VERSION = "0.1";

$MANINV_URL = 'http://www.maninvestments.com.au/index.cfm?action=productprices&cat_id=5';

sub methods {return (maninv => \&maninv)}

{
	my @labels = qw/name last nav date isodate currency/;

	sub labels { return (maninv       => \@labels); }
}

# Man Investments Australia (ManInvestments)
# Man Investments provides free delayed quotes through their webpage.
#

sub maninv {
    my $quoter = shift;
    my @stocks = @_;
    return unless @stocks;
    my %info;
    my $date;
    my $isodate;

    my $ua = $quoter->user_agent;

    my $response = $ua->request(GET $MANINV_URL);
#	print %$response,"\n";

    unless ($response->is_success) {
	foreach my $stock (@stocks) {
	    $info{$stock,"success"} = 0;
	    $info{$stock,"errormsg"} = "HTTP session failed";
	}
	return wantarray() ? %info : \%info;
    }

    my $tel = HTML::TableExtract->new(headers => [qw(Fund Net Rising)]);
    $tel->parse($response->content);

    foreach my $ts ($tel->table_states) {
	my ($depth, $count) = $ts->coords;
#	print "Table (", join(',', $ts->coords), "):\n", $depth, ',' , $count;

	my $te = HTML::TableExtract->new(depth => $depth, count => $count);

	$te->parse($response->content);


	# Extract table contents.
	my @rows;
	unless (@rows = $te->rows) {
	    foreach my $stock (@stocks) {
		$info{$stock,"success"} = 0;
		$info{$stock,"errormsg"} = "Failed to parse HTML table.";
	    }
	    return wantarray() ? %info : \%info;
	}
#	foreach my $row (@rows) {
#	    print(join(',',@$row),"\n");
#	}

	# Pack the resulting data into our structure.
	foreach my $row (@rows) {
	    my $name = shift(@$row);
	    $name =~ tr/\000-\040\200-\377/ /s;
	    $name =~ s/^ *//;
	    $name =~ s/ *$//;
	    # Map between Names and codes. There are no standard codes
	    # for these so I made them up.
	    my %map = ('OM-IP 220 Ltd' => 'OMIP220',
		       'Series 2 OM-IP 220 Ltd' => 'OMS2220',
		       'Series 3 OM-IP 220 Ltd' => 'OMS3220',
		       'Series 4 OM-IP 220 Ltd' => 'OMS4220',
		       'Series 5 OM-IP 220 Ltd' => 'OMS5220',
		       'Series 6 OM-IP 220 Ltd' => 'OMS6220',
		       'Series 7 OM-IP 220 Ltd' => 'OMS7220',
		       'Series 8 OM-IP 220 Ltd' => 'OMS8220',
		       'Series 9 OM-IP 220 Ltd' => 'OMS9220',
		       'OM-IP 320 Diversified Ltd' => 'OMIP320',
		       'OM-IP Strategic Ltd' => 'OMIPS',
		       'OM-IP Strategic Series 2 Ltd' => 'OMIPS2S',
		       'OM-IP Hedge Plus Ltd' => 'OMIPHP');
	    

	    {
		local $_ = $$row[0];
		tr/\000-\040\200-\377/ /s;
		if (/Net Asset Value as at (.*)$/) {
		    my @date_list = split(' ', $1);
		    $date_list[1] = { January => 1,
				      February => 2,
				      March => 3,
				      April => 4,
				      May => 5,
				      June => 6,
				      July => 7,
				      August => 8,
				      September => 9,
				      October => 10,
				      November => 11,
				      December => 12
				      }->{$date_list[1]};
		    $date = "$date_list[1]/$date_list[0]/$date_list[2]";
		    $isodate = sprintf "%4d-%02d-%02d", $date_list[2], $date_list[0], $date_list[1];
#		    print "US Date: $date\n";
#		    print "ISO Date: $date\n";
		}
	    }
	    # Delete spaces and '*' which sometimes appears after the code.
	    # Also delete high bit characters.
	    my $stock = $map{$name};
	    if (! $stock) { next};
	    $info{$stock,'symbol'} = $stock;
	    $info{$stock,'name'} = $name;
	    $info{$stock,'nav'} = shift(@$row);
	    $info{$stock,'nav'} =~ tr/ $\000-\037\200-\377//d; 
	    $info{$stock,'last'} = $info{$stock,'nav'};
	    $info{$stock,'date'} = $date;
	    $info{$stock,'isodate'} = $isodate;
	    $info{$stock, "currency"} = "AUD";
	    $info{$stock, "method"} = "maninv";
	    $info{$stock, "exchange"} = "Man Investments Australia";
	    $info{$stock, "success"} = 1;
#	    print $info{$stock,'symbol'};
#	    foreach my $label (qw/name nav last date currency method exchange success/) {
#		print ", ", $info{$stock,$label};
#	    }
#	    print "\n";
	}

    }
    # All done.

    return %info if wantarray;
    return \%info;
}

1;

=head1 NAME

Finance::Quote::ManInvestments	- Obtain quotes from Man Investments Australia.

=head1 SYNOPSIS

    use Finance::Quote;

    $q = Finance::Quote->new;

    %stockinfo = $q->fetch("maninv","BHP");	   # Only query Man Investments

=head1 DESCRIPTION

This module obtains information from Man Investments Australia
(formerly OM Strategic Investments)

http://www.maninvestments.com.au/

This module is loaded by default on a Finance::Quote object.  It's
also possible to load it explicity by placing "ManInvestments" in the argument
list to Finance::Quote->new().

=head1 LABELS RETURNED

The following labels may be returned by Finance::Quote::ManInvestments:
name, date, isodate, bid, ask, last, currency and price.

=head1 SEE ALSO

Man Investments Australia, http://www.maninvestments.com.au/

Finance::Quote::ManInvestments.

=cut
