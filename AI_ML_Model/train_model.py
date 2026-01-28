import pandas as pd
import numpy as np
import torch
import torch.nn as nn
from datetime import datetime
from math import sin, cos, pi
from sklearn.preprocessing import LabelEncoder
import coremltools as ct
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder


"""
Training Script for the task-priority classification model found in the watch app.

This script contains a neural network used to generate task-priority predictions in a watchOS application. The trained model is later exported to CoreML for on-device inference.
"""

# Load Training Data
trainingDataPath = "TrainingDataset.csv"
trainingData = pd.read_csv(trainingDataPath) # reads the training data
print(" CSV Columns:", trainingData.columns.tolist())

HAS_CONTEXT = "contextLocation" in trainingData.columns

# Encoders maps used to convert the strings into indicis for the one hot encoding func

taskTypeIds = {"Work":0,"Health":1,"Home":2,"Leisure":3,"Other":4}
locationIds   = {"Work":0,"Home":1,"Gym":2,"Supermarket":3,"Park":4,"Clinic":5,"Other":6}

# One hot encoding was found using this documentation
# https://scikit-learn.org/stable/modules/generated/sklearn.preprocessing.OneHotEncoder.html
#  allows us to store each task and location independently in a vector so the nn can differentiate
def one_hot(idx, size):
    vector = np.zeros(size, dtype=np.float32) # Start with Zero
    if idx is not None and 0 <= idx < size: # only set to one if index is valid idx = index
        vector[idx] = 1.0
    return vector # Return the vector

# Number of features = 23 so 23 dims
# 11 numeric + 5 (task type one-hot) + 7 (location one-hot)
# ------------------------------------------------------------
dateTime = datetime.now()
highRankedWords = ["urgent","asap","deadline","important","critical","boss","meeting","presentation","review"]

def encode_row(row) -> np.ndarray:
    dt = pd.to_datetime(row["dateTime"])
    hour = int(dt.hour)
    day  = int(dt.weekday())
    # For hours and days of week to make sure the model seems them for what they truly are
    # As 00:00 and 23:00 usually seem far apart but in reality they are close
    # This represents them in a way that they appear close together
    hourSin = sin(2*pi*hour/24.0)
    hourCos = cos(2*pi*hour/24.0)
    daySin  = sin(2*pi*day/7.0)
    dayCos  = cos(2*pi*day/7.0)

    # calculates the hours to ensuring it never goes below 0
    hours_until = max(0.0, (dt - dateTime).total_seconds()/3600.0)
    # Caps the hour limit to 336 hours (2 weeks) so tasks exceeding that are treated as equally far away
    limitedHours = float(min(hours_until, 336.0))
    # Create a normalised score
    urgency_decay = 1.0 - (limitedHours / 336.0)

    # Text extraction to get the title, and description and combine it into lowercase text
    title = str(row.get("title",""))
    desc  = str(row.get("description",""))
    text  = (title + " " + desc).lower()
    # Words in the title are weighted 50% stronger in the total word count
    totalWordCount = 1.5*len(title.split()) + len(desc.split())
    char_count = len(text)
    # Pads text with spaces so we can check each word
    paddedText = f" {text} "
    # checks the amount of times urgent words appear in the text
    urgentWordCount = sum(1 for w in highRankedWords if f" {w} " in paddedText)
    # Retrieve the indexes for the current tasks, not found return other
    taskTypeIndex  = taskTypeIds.get(row["taskType"], taskTypeIds["Other"])
    locationIndex = locationIds.get(row["location"], locationIds["Other"])
    # one hot encodings
    taskTypeOH   = one_hot(taskTypeIndex, len(taskTypeIds)) # 5 one hot encodings
    locationOH  = one_hot(locationIndex, len(locationIds)) # 7 one hot encodings

    # Checks to see if there is a match between location and context
    contextMatch = 0.0
    if HAS_CONTEXT:
        contextMatch = 1.0 if row["location"] == row["contextLocation"] else 0.0

    # Converts duration to float
    try:
        duration = float(row["duration"])
    except Exception:
        duration = 0.0

    # 11 numeric features
    numeric = np.array([
        limitedHours, duration,
        totalWordCount, char_count, urgentWordCount,
        urgency_decay, hourSin, hourCos, daySin, dayCos,
        contextMatch
    ], dtype=np.float32)
    # Combine all features to make all 23
    return np.concatenate([numeric, taskTypeOH, locationOH]).astype(np.float32)
# Do the following encoding for all rows of the training data
X = np.stack([encode_row(row) for _, row in trainingData.iterrows()], axis=0)

# Convert priority strings into integer classes
le = LabelEncoder()
y = le.fit_transform(trainingData["priority"].values) # e.g. High = 0, low = 2
# Store labels
classLabels = le.classes_.tolist()


# Standardize numeric block
# First 11 features are numeric
NUMERIC_DIMS = 11
# computes mean and standard deviation of numeric features
mu = X[:, :NUMERIC_DIMS].mean(axis=0, keepdims=True)
sd = X[:, :NUMERIC_DIMS].std(axis=0, keepdims=True) + 1e-8
# standardizes numeric features to improve training stability
X[:, :NUMERIC_DIMS] = (X[:, :NUMERIC_DIMS] - mu) / sd
# X is the full dataset and y is the integer encoded labels


# PyTorch model for a Multi Layer Perceptron neural network (nn)
# Built using PyTorch nn module class
# Aided using https://docs.pytorch.org/tutorials/beginner/blitz/neural_networks_tutorial.html

class MLP(nn.Module):
    def __init__(self, input_size, hidden1, hidden2, outputSize):
        super().__init__()
        # First fully connected layer, input features with hidden layer 1
        self.fc1 = nn.Linear(input_size, hidden1)
        # Relu is the non linear activation function
        self.relu1 = nn.ReLU()
        # Secound fully connected layer, with hidden layer 1 and hidden layer 2
        self.fc2 = nn.Linear(hidden1, hidden2)
        self.relu2 = nn.ReLU()
        # Output layer with hidden layer 2 going to the number of classes
        self.fc3 = nn.Linear(hidden2, outputSize)

    def forward(self, x):
        # Passes the input through the first layer, applying ReLU
        x = self.relu1(self.fc1(x))
        # Now the secound layer
        x = self.relu2(self.fc2(x))
        # finally the output layer with no ReLU activation
        return self.fc3(x)

print("Training neural network")
# Converts the training data into Torch tensor layers
X_tensor = torch.tensor(X, dtype=torch.float32) # The Features
y_tensor = torch.tensor(y, dtype=torch.long)    # The Labels

# Specify the model paramaters
# Input size is equal to the number of features
# Hidden layers have 32 neurons for the first layer and 16 for the next
# The output size is equal to the number of priority classes
# Aided using https://pytorch.org/tutorials/beginner/basics/optimization_tutorial.html
model = MLP(input_size=X.shape[1], hidden1=32, hidden2=16, outputSize=len(classLabels))
# Using CrossEntropyLoss for classification problems like this one
lossFunc = nn.CrossEntropyLoss()
# Using the Adam algorithm as worked best, with the following parameters
optimizer = torch.optim.Adam(model.parameters(), lr=0.003, weight_decay=1e-4)

EPOCHS = 180 # Ideal amount found in neural evaluation testing
for epoch in range(EPOCHS+1):
    # Reset gradients for each epoch
    optimizer.zero_grad()
    logits = model(X_tensor) # Compute predictions store in logits
    loss = lossFunc(logits, y_tensor) # Compare predictions to labels to find loss
    loss.backward() # Backward step, compute gradients
    optimizer.step() # Update model weights using the gradients
    if epoch % 50 == 0:
        print(f"Epoch {epoch:3d} - Loss: {loss.item():.4f}")


# Extract weights and biases from the model
# Need to detatch to ensure they PyTorch knows we dont need to process with it anymore
# Dont need gradients so detatch
W1 = model.fc1.weight.detach().cpu().numpy()
b1 = model.fc1.bias.detach().cpu().numpy()
W2 = model.fc2.weight.detach().cpu().numpy()
b2 = model.fc2.bias.detach().cpu().numpy()
W3 = model.fc3.weight.detach().cpu().numpy()
b3 = model.fc3.bias.detach().cpu().numpy()

# Fold standardization into the first layer
# This prevents the need for doing this in Swift to remove complexity
# Try to do as much preprocessing as we can, this is a trick to bake it into weights

# Make copies so we dont overwrite the original still needed for processing
W1Adjustments = W1.copy()
b1Adjustments = b1.copy()

numericWeights = W1[:, :NUMERIC_DIMS] # extract weights for the numeric input features
scale = 1.0 / sd.reshape(-1) # Std for each feature
numericWeightsScaled = numericWeights * scale # Apply scaling to numeric features
meamVector = mu.reshape(-1) # Compute the shift caused by subtractign the mean during std
shift = (numericWeightsScaled @ meamVector)
# Replace original weight with the scaled version
W1Adjustments[:, :NUMERIC_DIMS] = numericWeightsScaled
# Adjust the bias so the mean shift is accounted for
b1Adjustments = b1 - shift


# CoreML export 23 input features
# Input dimensions is equal to the number of features
inputDimensions = X.shape[1]
inputFeatures = [("input", datatypes.Array(inputDimensions))]
outputFeatures = [("prob_output", datatypes.Array(len(classLabels)))]
# Create the CoreML neural network using the builder object

# The following network builder was aided with Apples documentation
# https://apple.github.io/coremltools/source/coremltools.models.neural_network.html

builder = NeuralNetworkBuilder(inputFeatures, outputFeatures)

# The same process used before to train the model so commenting seemed not needed
builder.add_inner_product(
    name="dense1",
    input_name="input",
    output_name="h1",
    input_channels=inputDimensions,
    output_channels=32,
    W=W1Adjustments, b=b1Adjustments, has_bias=True
)
builder.add_activation("relu1", "RELU", "h1", "relu1_out")

# Dense2
builder.add_inner_product(
    name="dense2",
    input_name="relu1_out",
    output_name="h2",
    input_channels=32,
    output_channels=16,
    W=W2, b=b2, has_bias=True
)
builder.add_activation("relu2", "RELU", "h2", "relu2_out")

# Dense3  with Softmax
builder.add_inner_product(
    name="dense3",
    input_name="relu2_out",
    output_name="scores",
    input_channels=16,
    output_channels=len(classLabels),
    W=W3, b=b3, has_bias=True
)

builder.add_softmax("softmax", "scores", "prob_output")

# Save the CoreML model.
mlmodel = ct.models.MLModel(builder.spec)
mlmodel.save("PriorityNN.mlmodel")
print(f" Model saved as 'PriorityNN.mlmodel' with labels: {classLabels}")

