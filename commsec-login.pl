#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;
use LWP::UserAgent;
use HTTP::Request::Common qw{ POST };
use HTTP::Cookies;

# Date run and mypath
($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
my $starttime = "$year-$month-$day-$hour:$min:$sec";
my ($pname, $mypath, $type) = fileparse($0,qr{\..*});

# File and directories
$logfile = "$mypath/$pname.log";
$htmldir = "$mypath/html";
mkdir $htmldir unless -d $htmldir;

# SMTP
my $smtpserver = 'mail.7r.com.au';
my $smtpport = 465;
my $smtpuser   = 'shares@7r.com.au';
my $smtppassword = 'D3l3t312';
my $mailfrom = "shares\@7r.com.au";
my $mailto = "sstrijak\@7r.com.au";
my $subject = "$pname on $starttime";
my $otomessage = "";
my $message = "";

# mySQL
my $dbname = "shares";
my $dbhost = "localhost";
my $dbport = 3306;
my $dbuser = "shares";
my $dbpassword = "D3l3t312";
my $dbtable = "stocks";

# Flow control and reporting
my $keepgoing = 1;

# Script data
my $ua;
my $cookie_jar;

my $get_keyms = 1;
my $get_fcast = 1;
my $get_finan = 1;
my $get_coinf = 1;
my $get_anals = 1;
my $get_peers = 1;
my $get_divid = 1;
my $get_calen = 1;
my $get_hldrs = 1;


my $commsec_login_url = "https://www2.commsec.com.au/Public/HomePage/Login.aspx";
my $commsec_stock_url = "https://www2.commsec.com.au/Private/MarketPrices/QuoteSearch/QuoteSearch.aspx?stockCode=BAL";
my $commsec_keyms_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/KeyMeasures.aspx?stockCode=BAL";
my $commsec_fcast_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Forecasts.aspx?stockCode=BAL";
my $commsec_finan_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Financials.aspx?stockCode=BAL";
my $commsec_coinf_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/CompanyInfo.aspx?stockCode=BAL";
my $commsec_anals_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Analysis.aspx?stockCode=BAL";
my $commsec_peers_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/PeerAnalysis.aspx?stockCode=BAL";
my $commsec_divid_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Dividends.aspx?stockCode=BAL";
my $commsec_calen_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/CorporateCalendar.aspx?stockCode=BAL";
my $commsec_hldrs_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Shareholders.aspx?=BAL";

my $commsecuser = "52934144";
my $commsecpass = "Wb1GtEFa!@";

########## Read parameters and display help message

open LOG, ">>", $logfile;

$ua = LWP::UserAgent->new;
$cookie_jar = HTTP::Cookies->new;

my $request = POST( $commsec_login_url, [
	'ctl00$cpContent$txtLogin' => $commsecuser,
	'ctl00$cpContent$txtPassword' => $commsecpass,
	'__EVENTTARGET' => "",
	'__EVENTARGUMENT' => "",
	'ctl00$cpContent$btnLogin' => "",
] );

$response = $ua->request( $request );
$cookie_jar->extract_cookies( $response );
$ua->cookie_jar( $cookie_jar );

my $dsn = "DBI:mysql:database=$dbname;host=$dbhost;port=$dbport";
my $dbh = DBI->connect($dsn, $dbuser, $dbpassword);
my $error = $dbh->{'mysql_error'};

if ( $error)
{
	$thismessage = "Error connecting to database: $error";
	logentry ( $thismessage );
	$message .= "$thismessage\n";
	$keepgoing = 0;
}

if ($keepgoing)
{
#	$sql = "SELECT distinct code FROM daily  where code > 'SLM' and code NOT IN(SELECT code FROM indexes) order by code";
	$sql = "SELECT distinct code FROM daily  where code like '___' and code > 'AUQ' and code NOT IN(SELECT code FROM indexes) order by code";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	while(@row = $sth->fetchrow_array())
	{
		$stockcount++;
		if ( $stockcount % 100 == 0 )
		{
#			sendreport ( "Completed $stockcount" );	
		}
		$code = $row[0];
		print $code."\n";

		if ( $get_keyms )
		{
			$commsec_keyms_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/KeyMeasures.aspx?stockCode=".$code;
			$response = $ua->get($commsec_keyms_url);
			$content = $response->content();
			open OUT, ">", "$htmldir/$code-KeyMeasures.html";
			print OUT $content;
			close OUT;
			sleep 2;
		}
		if ( $get_finan )
		{
			$commsec_finan_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Financials.aspx?stockCode=".$code;
			$response = $ua->get($commsec_finan_url);
			$content = $response->content();
			open OUT, ">", "$htmldir/$code-Financials.html";
			print OUT $content;
			close OUT;
			sleep 2;
		}
		if ( $get_coinf )
		{

			$commsec_coinf_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/CompanyInfo.aspx?stockCode=".$code;
			$response = $ua->get($commsec_coinf_url);
			$content = $response->content();
			open OUT, ">", "$htmldir/$code-CompanyInfo.html";
			print OUT $content;
			close OUT;
			sleep 2;
		}
		if ( $get_anals )
		{

			$commsec_anals_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Analysis.aspx?stockCode=".$code;
			$response = $ua->get($commsec_anals_url);
			$content = $response->content();
			open OUT, ">", "$htmldir/$code-Analysis.html";
			print OUT $content;
			close OUT;
			sleep 2;
		}
		if ( $get_peers )
		{

			$commsec_peers_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/PeerAnalysis.aspx?stockCode=".$code;
			$response = $ua->get($commsec_peers_url);
			$content = $response->content();
			open OUT, ">", "$htmldir/$code-PeerAnalysis.html";
			print OUT $content;
			close OUT;
			sleep 2;
		}
		if ( $get_divid )
		{

			$commsec_divid_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Dividends.aspx?stockCode=".$code;
			$response = $ua->get($commsec_divid_url);
			$content = $response->content();
			open OUT, ">", "$htmldir/$code-Dividends.html";
			print OUT $content;
			close OUT;
			sleep 2;
		}
		if ( $get_calen )
		{

			$commsec_calen_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/CorporateCalendar.aspx?stockCode=".$code;
			$response = $ua->get($commsec_calen_url);
			$content = $response->content();
			open OUT, ">", "$htmldir/$code-CorporateCalendar.html";
			print OUT $content;
			close OUT;
			sleep 2;
		}
		if ( $get_hldrs )
		{
			$commsec_hldrs_url = "https://www2.commsec.com.au/Private/MarketPrices/CompanyProfile/Shareholders.aspx?=".$code;
			$response = $ua->get($commsec_hldrs_url);
			$content = $response->content();
			open OUT, ">", "$htmldir/$code-Shareholders.html";
			print OUT $content;
			close OUT;
			sleep 2;
		}
		sleep int(rand(10));
	}
	$sth->finish();
}

# closing
#sendreport ( "Completed" );
close LOG;

sub sendreport () {
	my $message = $_[0];
	my $smtp = Net::SMTP::SSL->new($smtpserver, Port=>$smtpport, Timeout => 10, Debug => 1);
	$smtp->auth($smtpuser,$smtppassword);
	$smtp->mail($mailfrom);
	$smtp->to($mailto);
	$smtp->recipient($mailto);
	$smtp->data();
	$smtp->datasend("To: $mailto\n");
	$smtp->datasend("From: $mailfrom\n");
	$smtp->datasend("Subject: $subject\n");
	$smtp->datasend("\n"); # done with header
	$smtp->datasend($message);
	$smtp->dataend();
	
	$smtpcode = $smtp->code();
	$smtpmsg = $smtp->message();
	
	$smtp->quit(); # all done. message sent.
	logentry ( "Mail send result: $smtpcode: $smtpmsg" );
}

sub logentry () {
	my $entry = $_[0];
	print STDOUT "$entry\n";
	($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
	$now = "$year-$month-$day-$hour:$min:$sec";
	print LOG $now; 
	print LOG ": $entry\n"; 
}

