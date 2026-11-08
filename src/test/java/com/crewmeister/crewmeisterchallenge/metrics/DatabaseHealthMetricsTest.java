package com.crewmeister.crewmeisterchallenge.metrics;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.sql.Connection;
import java.sql.SQLException;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;

class DatabaseHealthMetricsTest {

  @Test
  void reportsOneWhenConnectionIsValid() throws Exception {
    DataSource ds = mock(DataSource.class);
    Connection c = mock(Connection.class);
    when(ds.getConnection()).thenReturn(c);
    when(c.isValid(1)).thenReturn(true);
    SimpleMeterRegistry registry = new SimpleMeterRegistry();
    new DatabaseHealthMetrics(ds).bindTo(registry);
    assertThat(registry.get("app.database.up").gauge().value()).isEqualTo(1.0);
  }

  @Test
  void reportsZeroWhenDatabaseIsUnreachable() throws Exception {
    DataSource ds = mock(DataSource.class);
    when(ds.getConnection()).thenThrow(new SQLException("down"));
    SimpleMeterRegistry registry = new SimpleMeterRegistry();
    new DatabaseHealthMetrics(ds).bindTo(registry);
    assertThat(registry.get("app.database.up").gauge().value()).isEqualTo(0.0);
  }
}
