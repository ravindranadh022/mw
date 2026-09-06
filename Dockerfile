FROM tomcat:9.0
COPY target/maven-web-project1.war /usr/local/tomcat/webapps/maven-web-project1.war
