package com.crewmeister.crewmeisterchallenge.metrics;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.binder.MeterBinder;
import java.sql.Connection;
import javax.sql.DataSource;
import org.springframework.stereotype.Component;

/**
 * Publishes {@code app_database_up} (1 = a pooled connection validated within 1s, 0 = not).
 * Evaluated on every scrape, so Prometheus sees the database as the application sees it.
 */
@Component
public class DatabaseHealthMetrics implements MeterBinder {

  private final DataSource dataSource;

  public DatabaseHealthMetrics(DataSource dataSource) {
    this.dataSource = dataSource;
  }

  @Override
  public void bindTo(MeterRegistry registry) {
    Gauge.builder("app.database.up", this, DatabaseHealthMetrics::probe)
        .description("1 if the application can obtain and validate a database connection")
        .register(registry);
  }

  double probe() {
    try (Connection connection = dataSource.getConnection()) {
      return connection.isValid(1) ? 1.0 : 0.0;
    } catch (Exception e) {
      return 0.0;
    }
  }
}
