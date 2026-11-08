package com.crewmeister.crewmeisterchallenge.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.crewmeister.crewmeisterchallenge.model.User;
import com.crewmeister.crewmeisterchallenge.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

/** Fast, Docker-free unit tests of the controller logic. */
class UserControllerTest {

  private UserRepository repository;
  private MockMvc mvc;

  @BeforeEach
  void setUp() {
    repository = mock(UserRepository.class);
    mvc = MockMvcBuilders.standaloneSetup(new UserController(repository)).build();
  }

  private static User user(Long id, String name) {
    User u = new User();
    u.setId(id);
    u.setName(name);
    return u;
  }

  @Test
  void getReturnsGreeting() throws Exception {
    when(repository.findById(7L)).thenReturn(user(7L, "Carol"));
    mvc.perform(get("/user").param("id", "7"))
        .andExpect(status().isOk())
        .andExpect(content().string("Greetings from Crewmeister, Carol!"));
  }

  @Test
  void getUnknownIdIs404() throws Exception {
    when(repository.findById(8L)).thenReturn(null);
    mvc.perform(get("/user").param("id", "8")).andExpect(status().isNotFound());
  }

  @Test
  void postPersistsAndSetsLocation() throws Exception {
    when(repository.save(any(User.class))).thenAnswer(i -> {
      User u = i.getArgument(0);
      u.setId(42L);
      return u;
    });
    mvc.perform(post("/user").contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Dave\"}"))
        .andExpect(status().isOk())
        .andExpect(header().string("Location", "/user?id=42"))
        .andExpect(content().string("Greetings from Crewmeister, Dave!"));
  }

  @Test
  void postWithoutNameDoesNotPersist() throws Exception {
    mvc.perform(post("/user").contentType(MediaType.APPLICATION_JSON).content("{\"x\":1}"))
        .andExpect(status().isOk())
        .andExpect(content().string("Error parsing JSON"));
    verify(repository, never()).save(any());
  }
}
