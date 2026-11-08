package com.crewmeister.crewmeisterchallenge;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

/**
 * Black-box contract tests over real HTTP against a real MySQL (Flyway migration included).
 * These pin the API contract the release verification relies on.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureObservability // Spring Boot disables metric exporters in tests by default
@Import(MySqlTestConfiguration.class)
class UserApiIntegrationTest {

  @Autowired
  TestRestTemplate http;

  private ResponseEntity<String> post(String json) {
    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_JSON);
    return http.postForEntity("/user", new HttpEntity<>(json, headers), String.class);
  }

  @Test
  void flywaySeedUserIsReadable() {
    ResponseEntity<String> response = http.getForEntity("/user?id=1", String.class);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isEqualTo("Greetings from Crewmeister, Alice!");
  }

  @Test
  void createdUserIsPersistedAndReadableByLocation() {
    ResponseEntity<String> created = post("{\"name\":\"Bob\"}");
    assertThat(created.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(created.getBody()).isEqualTo("Greetings from Crewmeister, Bob!");

    URI location = created.getHeaders().getLocation();
    assertThat(location).isNotNull();
    assertThat(location.toString()).startsWith("/user?id=");

    ResponseEntity<String> fetched = http.getForEntity(location.toString(), String.class);
    assertThat(fetched.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(fetched.getBody()).isEqualTo("Greetings from Crewmeister, Bob!");
  }

  @Test
  void unknownUserIsNotFoundInsteadOfServerError() {
    ResponseEntity<String> response = http.getForEntity("/user?id=999999", String.class);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void missingIdParameterIsBadRequest() {
    assertThat(http.getForEntity("/user", String.class).getStatusCode())
        .isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void invalidJsonKeepsLegacyBehaviour() {
    // Characterisation test: the original service answers 200 + this text. Documented in README.
    ResponseEntity<String> response = post("not json");
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isEqualTo("Error parsing JSON");
    assertThat(response.getHeaders().getLocation()).isNull();
  }

  @Test
  void readinessIncludesDatabaseAndLivenessDoesNot() {
    String readiness = http.getForObject("/actuator/health/readiness", String.class);
    assertThat(readiness).contains("\"status\":\"UP\"").contains("\"db\"");
    String liveness = http.getForObject("/actuator/health/liveness", String.class);
    assertThat(liveness).contains("\"status\":\"UP\"").doesNotContain("\"db\"");
  }

  @Test
  void prometheusExposesHttpJvmAndDatabaseMetrics() {
    http.getForEntity("/user?id=1", String.class); // make sure an HTTP sample exists
    String metrics = http.getForObject("/actuator/prometheus", String.class);
    assertThat(metrics)
        .contains("http_server_requests_seconds_count")
        .contains("jvm_memory_used_bytes")
        .contains("hikaricp_connections_active")
        .contains("app_database_up{application=\"app\"} 1.0");
  }

  @Test
  void sensitiveActuatorEndpointsAreNotExposed() {
    for (String endpoint : new String[] {"env", "beans", "heapdump", "threaddump", "configprops"}) {
      assertThat(http.getForEntity("/actuator/" + endpoint, String.class).getStatusCode())
          .as(endpoint)
          .isEqualTo(HttpStatus.NOT_FOUND);
    }
  }
}
