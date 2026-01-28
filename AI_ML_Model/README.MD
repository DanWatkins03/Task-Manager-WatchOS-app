# Machine Learning Model

This directory contains the Python code to train and evaluate the task priorisation model found in the watchOS application.

## Contents
- 'train_model.py' - trains the neural network on extracted task features
- 'evaluate_model.py' - evaluates model performance and generates metric graphs such as a confusion matrix

## Model evaluation

Performance of the model was evaluated using techniques such as a confusion matrix, and training curves seen in the screenshots below. The confusion matrix highlights the models strong performance in low to high classified tasks, with most misclassifcation found in borderline medium priority classes.

<p float="left">
  <img src="../Screenshots/ConfusionMatrix.png" />
  <img src="../Screenshots/TrainValGraph.png" />
</p>
