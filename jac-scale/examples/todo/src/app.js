import {__jacJsx, __jacSpawn} from "@jac-client/utils";
import { useState } from "react";
function app() {
  let [todos, setTodos] = useState([]);
  let [input, setInput] = useState("");
  async function addTodo() {
    if (!input.trim()) {
      return;
    }
    let response = await __jacSpawn("create_todo", "", {"text": input.trim()});
    let new_todo = response.reports[0][0];
    setTodos(todos.concat([new_todo]));
    setInput("");
  }
  return __jacJsx("div", {}, [__jacJsx("h2", {}, ["My Todos"]), __jacJsx("input", {"value": input, "onChange": e => {
    setInput(e.target.value);
  }, "onKeyPress": e => {
    if (e.key === "Enter") {
      addTodo();
    }
  }}, []), __jacJsx("button", {"onClick": addTodo}, ["Add Todo"]), __jacJsx("div", {}, [todos.map(todo => {
    return __jacJsx("div", {"key": todo._jac_id}, [__jacJsx("span", {}, [todo.text])]);
  })])]);
}
export { app };
