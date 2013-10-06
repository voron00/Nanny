#!/usr/bin/perl -w

system 'ppm install DBD::Mysql';
system 'ppm install Time::Duration';
system 'ppm install Geo-Inverse';
system 'ppm install Geo-Constants';
system 'ppm install Geo-Ellipsoids';
system 'ppm install Geo-Functions';
sleep 1;
system 'ppm upgrade --install';
sleep 1;
system '@pause';