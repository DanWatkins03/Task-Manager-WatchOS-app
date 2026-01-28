import pandas as pd
import numpy as np
import torch
import torch.nn as nn
from datetime import datetime
from math import sin, cos, pi
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
import matplotlib.pyplot as plt
import seaborn as sns

"""
Evaluation Script for the task priority classification model found in the watchOS app.

Generates metrics and visualisations such as a confusion matrix to access model performance.
"""


DROPOUT_P = 0.2
VAL_CHECK_EVERY = 1
# Seeds ensure consistent runs otherwise output is changed as training can have some varying data
SEED = 42
np.random.seed(SEED)
torch.manual_seed(SEED)


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
dateTime = datetime.now()  # fixed once for consistent "hours_until"
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


y_cat = trainingData["priority"].astype("category")
y = y_cat.cat.codes.to_numpy()
classLabels = y_cat.cat.categories.tolist()



NUMERIC_DIMS = 11

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
        x = self.relu1(self.fc1(x))
        x = self.relu2(self.fc2(x))
        return self.fc3(x)


# Cross-Validation using Straified k fold
# aided with the documentation at https://scikit-learn.org/stable/modules/generated/sklearn.model_selection.StratifiedKFold.html

skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)
# store all predictions and targets across the folds
savePredictions, saveTargets = [], []
# store all the losses and validation losses across folds
saveFoldLosses = []
saveFoldValLosses = []


for fold, (trainIndex, valIndex) in enumerate(skf.split(X, y)):
    print(f"\n Fold {fold + 1}/{5}")

    # Split numpy arrays into their train and val for current fold
    X_train_np, X_val_np = X[trainIndex].copy(), X[valIndex].copy()
    y_train_np, y_val_np = y[trainIndex].copy(), y[valIndex].copy()

    # Standardize numeric block by train stats only
    mu = X_train_np[:, :NUMERIC_DIMS].mean(axis=0, keepdims=True)
    sd = X_train_np[:, :NUMERIC_DIMS].std(axis=0, keepdims=True) + 1e-8
    X_train_np[:, :NUMERIC_DIMS] = (X_train_np[:, :NUMERIC_DIMS] - mu) / sd
    X_val_np[:, :NUMERIC_DIMS]   = (X_val_np[:, :NUMERIC_DIMS]   - mu) / sd

    # convert them to PyTorch sensors for training
    X_train = torch.tensor(X_train_np, dtype=torch.float32)
    X_val   = torch.tensor(X_val_np, dtype=torch.float32)
    y_train = torch.tensor(y_train_np, dtype=torch.long)
    y_val   = torch.tensor(y_val_np, dtype=torch.long)

    # Weights for possible adjusting, changing them did not seem to effect results much
    # typically made one class better but then another worse
    weights = torch.tensor([1.0, 1.0, 1.0], dtype=torch.float32)  # High, Low, Medium

    lossFunc = nn.CrossEntropyLoss(weight=torch.tensor(weights, dtype=torch.float32))

    # Specify the model paramaters
    # Input size is equal to the number of features
    # Hidden layers have 32 neurons for the first layer and 16 for the next
    # The output size is equal to the number of priority classes
    # Aided using https://pytorch.org/tutorials/beginner/basics/optimization_tutorial.html
    model = MLP(input_size=X.shape[1], hidden1=32, hidden2=16, outputSize=len(classLabels))
    optimizer = torch.optim.Adam(model.parameters(), lr=0.003, weight_decay=1e-4)

    # Train with early stopping when validation loss diminishes
    trainLosses, valLosses = [], []
    bestVal = np.inf
    patience = 25
    bestState = None
    bestEpoch = -1

    # Train with early stopping on validation loss
    # aided with  https://docs.pytorch.org/tutorials/beginner/blitz/cifar10_tutorial.html#train-the-network

    for epoch in range(300):
        model.train()
        optimizer.zero_grad()
        logits = model(X_train)
        loss = lossFunc(logits, y_train)
        loss.backward()
        optimizer.step()
        trainLosses.append(loss.item())

        # Validation step check val score at every epoch
        if epoch % VAL_CHECK_EVERY == 0:
            model.eval()
            with torch.no_grad():
                val_logits = model(X_val)
                val_loss = lossFunc(val_logits, y_val).item()
            valLosses.append(val_loss)
            # track the best val loss and save the best weights for the model
            if val_loss < bestVal - 1e-6:
                bestVal = val_loss
                bestEpoch = epoch
                patience = 25
                bestState = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            else:
                patience -= 1
                if patience <= 0:
                    model.load_state_dict(bestState)
                    print(f"Epoch stopped early {epoch}, best validation loss {bestVal:.4f} at epoch {bestEpoch}")
                    break

        if epoch % 50 == 0:
            print(f"Epoch:{epoch:3d} | train loss: {loss.item():.4f} | validation loss {val_loss:.4f}")

   # Store losses
    saveFoldLosses.append(trainLosses)
    saveFoldValLosses.append(valLosses)

    # Predict on validation set
    model.eval() # Sets model toe evaluation mode to ensure it does not update
    with torch.no_grad():
        logits = model(X_val) # Forward pass on validation data
        # Predicted class labels
        preds = torch.argmax(logits, dim=1).cpu().numpy()
        # Class probabilities
        probs = torch.softmax(logits, dim=1).cpu().numpy()

    # Compute the validation accuracy using the built in accuracy_score func
    acc = accuracy_score(y_val_np, preds)
    print(f"Fold accuracy: {acc:.2f}")
    savePredictions.extend(preds)
    saveTargets.extend(y_val_np)

# Evaluation after all folds

print("\n Final Classification Report:")
# Automatically generates precision recall, f1-score per class
# Found at https://scikit-learn.org/stable/modules/generated/sklearn.metrics.classification_report.html
report = classification_report(saveTargets, savePredictions, target_names=classLabels)
print(report)
# Confusion matrix reference found at https://scikit-learn.org/stable/modules/generated/sklearn.metrics.confusion_matrix.html
cm = confusion_matrix(saveTargets, savePredictions)
# So values represent actual percentages so its readable
cm_norm = cm.astype("float") / cm.sum(axis=1, keepdims=True)

# Creates and plot the figure for confusion matrix
plt.figure(figsize=(8, 6))
sns.heatmap(cm_norm, annot=True, fmt=".2f", xticklabels=classLabels, yticklabels=classLabels, cmap="Blues")
plt.title("Normalized Confusion Matrix")
plt.xlabel("Predicted")
plt.ylabel("True")
plt.tight_layout()
plt.show()

# Plot the training and validation loss graph
plt.figure(figsize=(10, 6))
for i, (tr, va) in enumerate(zip(saveFoldLosses, saveFoldValLosses)):
    plt.plot(tr, alpha=0.6, label=f"Train Fold {i+1}")
    val_x = np.arange(0, len(va)*VAL_CHECK_EVERY, VAL_CHECK_EVERY)
    plt.plot(val_x, va, linestyle="--", alpha=0.8, label=f"Val Fold {i+1}")
plt.title("Training / Validation Loss per Epoch Across Folds")
plt.xlabel("Epoch")
plt.ylabel("Loss")
plt.legend(ncol=2)
plt.grid(True, alpha=0.3)
plt.tight_layout()
plt.show()
