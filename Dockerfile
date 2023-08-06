FROM debian:bullseye

RUN set -eux; \
	groupadd --system --gid 999 mysql; \
	useradd --system --uid 999 --gid 999 --home-dir /var/lib/mysql --no-create-home mysql

RUN apt update

RUN apt install gosu pkg-config build-essential cmake libncurses5-dev bison g++ libssl-dev libffi-dev zlib1g-dev libncurses5-dev libreadline-dev libevent-dev libcurl4-openssl-dev wget default-mysql-client -y

COPY my.cnf /etc/my.cnf

WORKDIR /tmp

RUN wget https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-5.7.41.tar.gz && \
    tar -xvf mysql-5.7.41.tar.gz && \
    cd mysql-5.7.41 && \
    cmake . -DDOWNLOAD_BOOST=1 -DWITH_BOOST=/tmp/boost && \
    make -j$(nproc) && \
    make install && \
    ln -s /usr/local/mysql/bin/mysqld /usr/local/bin/mysqld && \
    chmod +x /usr/local/bin/mysqld && \
    ln -n /usr/local/mysql/bin/mysql_tzinfo_to_sql /usr/local/bin/mysql_tzinfo_to_sql && \
    chmod +x /usr/local/bin/mysql_tzinfo_to_sql

RUN set -eux; \
# the "socket" value in the Oracle packages is set to "/var/lib/mysql" which isn't a great place for the socket (we want it in "/var/run/mysqld" instead)
# https://github.com/docker-library/mysql/pull/680#issuecomment-636121520
	grep -F 'socket=/var/lib/mysql/mysql.sock' /etc/my.cnf; \
	sed -i 's!^socket=.*!socket=/var/run/mysqld/mysqld.sock!' /etc/my.cnf; \
	grep -F 'socket=/var/run/mysqld/mysqld.sock' /etc/my.cnf; \
	{ echo '[client]'; echo 'socket=/var/run/mysqld/mysqld.sock'; } >> /etc/my.cnf; \
	\
# make sure users dumping files in "/etc/mysql/conf.d" still works
	! grep -F '!includedir' /etc/my.cnf; \
	{ echo; echo '!includedir /etc/mysql/conf.d/'; } >> /etc/my.cnf; \
	mkdir -p /etc/mysql/conf.d; \
# 5.7 Debian-based images also included "/etc/mysql/mysql.conf.d" so let's include it too
	{ echo '!includedir /etc/mysql/mysql.conf.d/'; } >> /etc/my.cnf; \
	mkdir -p /etc/mysql/mysql.conf.d; \
	\
# comment out a few problematic configuration values
	find /etc/my.cnf /etc/mysql/ -name '*.cnf' -print0 \
		| xargs -0 grep -lZE '^(bind-address|log)' \
		| xargs -rt -0 sed -Ei 's/^(bind-address|log)/#&/'; \
	\
# ensure these directories exist and have useful permissions
# the rpm package has different opinions on the mode of `/var/run/mysqld`, so this needs to be after install
	mkdir -p /var/lib/mysql /var/run/mysqld; \
	chown mysql:mysql /var/lib/mysql /var/run/mysqld; \
# ensure that /var/run/mysqld (used for socket and lock files) is writable regardless of the UID our mysqld instance ends up having at runtime
	chmod 1777 /var/lib/mysql /var/run/mysqld; \
	\
	mkdir /docker-entrypoint-initdb.d; \
  mkdir -p /var/lib/mysql-files; \
	\
	mysqld --version

RUN rm -rf /tmp/*

VOLUME /var/lib/mysql

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306 33060
CMD ["mysqld"]
