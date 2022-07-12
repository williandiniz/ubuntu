FROM ubi8/ubi:8.3

LABEL description="This is a custom httpd container image"
#MAINTAINER John Doe <jdoe@xyz.com>

RUN yum install -y httpd
RUN yum update 
ENV TZ=America/Sao_Paulo
RUN yum install -y tzdata

RUN yum install -y curl

RUN yum install -y php 
RUN yum install -y php php-gd 
RUN yum install -y curl
RUN yum install -y nano

RUN mkdir /tmp/n1
ENV LogLevel "info"
#ADD http://someserver.com/filename.pdf /var/www/html
#COPY ./src/ /var/www/html/
USER apache
ENTRYPOINT ["/usr/sbin/httpd"]
CMD ["-D", "FOREGROUND"]
