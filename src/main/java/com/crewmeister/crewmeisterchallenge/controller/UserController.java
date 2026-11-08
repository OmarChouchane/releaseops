package com.crewmeister.crewmeisterchallenge.controller;

import com.crewmeister.crewmeisterchallenge.model.User;
import com.crewmeister.crewmeisterchallenge.repository.UserRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
public class UserController {

  UserRepository userRepository;

  public UserController(UserRepository userRepository) {
    this.userRepository = userRepository;
  }

  @GetMapping( "/user")
  public String hello(@RequestParam Long id) {
    // get user from database
    User user = userRepository.findById(id);
    if (user == null) {
      // Previously this dereferenced null and surfaced as an HTTP 500.
      throw new ResponseStatusException(HttpStatus.NOT_FOUND, "User " + id + " not found");
    }
    return "Greetings from Crewmeister, " + user.getName() + "!";
  }

  /**
   * Response body and status are unchanged. The only addition is a {@code Location} header
   * ({@code /user?id=<id>}) so clients - and the release verification - can read back the
   * record they created without guessing its id.
   */
  @PostMapping( "/user")
  public ResponseEntity<String> helloPost(@RequestBody String body) {
    try {
      // Parse JSON string to get name
      ObjectMapper objectMapper = new ObjectMapper();
      JsonNode jsonNode = objectMapper.readTree(body);
      String name = jsonNode.get("name").asText();

      // Save user to database
      User user = new User();
      user.setName(name);
      User returnedUser = userRepository.save(user);

      return ResponseEntity.ok()
          .location(URI.create("/user?id=" + returnedUser.getId()))
          .body("Greetings from Crewmeister, " + returnedUser.getName() + "!");
    } catch (Exception e) {
      e.printStackTrace();
      // Legacy behaviour kept on purpose: invalid payloads answer 200 with this text.
      return ResponseEntity.ok("Error parsing JSON");
    }
  }

}
