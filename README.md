import numpy as np
import random


# 1. Input text

text = "the cat sat on the mat"

words = text.lower().split()

print("Words:", words)


# 2. Create vocabulary

vocab = sorted(list(set(words)))

word2idx = {}

for i, word in enumerate(vocab):
    word2idx[word] = i

idx2word = {}

for word, index in word2idx.items():
    idx2word[index] = word

V = len(vocab)

print("Vocabulary:", vocab)
print("Word to Index:", word2idx)


# 3. Create training pairs

window = 2

pairs = []

for i, word in enumerate(words):

    start = max(0, i - window)
    end = min(len(words), i + window + 1)

    for j in range(start, end):

        if i != j:

            center_index = word2idx[word]
            context_index = word2idx[words[j]]

            pairs.append((center_index, context_index))


print("Training Pairs:\n")

for center, context in pairs:

    center_word = idx2word[center]
    context_word = idx2word[context]

    print(center_word, "->", context_word)


# 4. Display target word and context words

print("\nTarget Word --> Context Words\n")

for i, word in enumerate(words):

    context = []

    start = max(0, i - window)
    end = min(len(words), i + window + 1)

    for j in range(start, end):

        if i != j:

            context.append(words[j])

    print(word, "-->", context)


# 5. One-hot encoding

def one_hot(index, vocab_size):

    vec = np.zeros(vocab_size)

    vec[index] = 1

    return vec


# 6. Create weights

embedding_dim = 10

W = np.random.randn(V, embedding_dim)

W_prime = np.random.randn(embedding_dim, V)


# 7. Softmax function

def softmax(x):

    max_value = np.max(x)

    exp = np.exp(x - max_value)

    total = np.sum(exp)

    result = exp / total

    return result


# 8. Forward pass

def forward(center):

    x = one_hot(center, V)

    h = np.dot(x, W)

    u = np.dot(h, W_prime)

    y = softmax(u)

    return x, h, u, y


# 9. Loss function

def loss(y, target):

    probability = y[target]

    result = -np.log(probability + 1e-9)

    return result


# 10. Train the model

learning_rate = 0.05

for epoch in range(100):

    total_loss = 0

    for center, target in pairs:

        x, h, u, y = forward(center)

        current_loss = loss(y, target)

        total_loss = total_loss + current_loss

        error = y.copy()

        error[target] = error[target] - 1

        dW_prime = np.outer(h, error)

        temp = np.dot(W_prime, error)

        dW = np.outer(x, temp)

        W_prime = W_prime - learning_rate * dW_prime

        W = W - learning_rate * dW

    if epoch % 10 == 0:

        print("Epoch", epoch, "Loss:", total_loss)


# 11. Display learned word embeddings

print("\nLearned Word Embeddings:\n")

for word in vocab:

    index = word2idx[word]

    vector = W[index]

    print(word, ":", vector)


# 12. Cosine similarity

def cosine(a, b):

    numerator = np.dot(a, b)

    denominator = np.linalg.norm(a) * np.linalg.norm(b)

    result = numerator / denominator

    return result


print("\nCosine Similarities\n")

for word in vocab:

    print("\n", word)

    for other in vocab:

        if word != other:

            word_index = word2idx[word]
            other_index = word2idx[other]

            vector1 = W[word_index]
            vector2 = W[other_index]

            similarity = cosine(vector1, vector2)

            print(other, ":", round(similarity, 4))


# 13. Predict context words

random_word = random.choice(vocab)

print("\nInput Word:", random_word)

center = word2idx[random_word]

x, h, u, y = forward(center)

predicted = np.argsort(y)[::-1]

print("\nPredicted Context Words:")

count = 0

for idx in predicted:

    if idx != center:

        word = idx2word[idx]
        probability = round(y[idx], 4)


        print(word, "Probability:", probability)

        count = count + 1

        if count == 3:
            break
