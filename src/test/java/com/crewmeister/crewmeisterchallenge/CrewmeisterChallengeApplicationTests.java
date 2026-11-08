package com.crewmeister.crewmeisterchallenge;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@SpringBootTest
@Import(MySqlTestConfiguration.class)
class CrewmeisterChallengeApplicationTests {

  @Test
  void contextLoads() {
  }

}
