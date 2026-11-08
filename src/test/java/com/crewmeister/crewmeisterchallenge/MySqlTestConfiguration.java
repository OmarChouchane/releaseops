package com.crewmeister.crewmeisterchallenge;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.MySQLContainer;

/** Real MySQL for integration tests: same engine and major version as the Helm chart. */
@TestConfiguration(proxyBeanMethods = false)
public class MySqlTestConfiguration {

  @Bean
  @ServiceConnection
  MySQLContainer<?> mysql() {
    return new MySQLContainer<>("mysql:8.4");
  }
}
