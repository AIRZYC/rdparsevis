# RdparseVis

RdparseVis is an interactive, web-based visualization tool designed to help computer science students understand the step-by-step execution of a Recursive Descent parser (`rdparse.rb`).

By generating a JSON timeline from the parser's execution, RdparseVis allows users to explore the parsing process—including trial-and-error mechanisms like backtracking—at their own pace, making the invisible "notional machine" observable.

## Features

* **Step-by-Step Visualization:** Walk through the parsing process exactly as the algorithm executes it.
* **Bidirectional Stepping:** Move forward and backward through the parser's execution history without restarting.
* **Dynamic Tree Generation:** Watch the Abstract Syntax Tree (AST) build, adapt, and backtrack dynamically.
* **Rule & Token Tracking:** Live indicators show which grammar rules are currently being attempted and which tokens are consumed.
* **Decoupled Architecture:** The visualizer runs entirely in the browser, strictly separated from the Ruby parsing logic.

## Prerequisites

* **Ruby:** Required to run the modified `RdparseVis.rb` and generate the JSON timeline log.
* **Web Browser:** Any modern web browser (Chrome, Firefox, Safari, Edge) to run the visualization interface.

## Project status

This project was developed as a part of a Bachelor of Science in Computer Engineering at Linköping Unversity 2026.


