import os

files = os.listdir("src/ids")

for file in files:
    counts = {}

    with open("src/ids/" + file) as f:
        contents = f.read()
        split = contents.split(" ")
        for w in split:
            if len(w) < 2:
                continue
            if w in counts:
                counts[w] += 1
            else:
                counts[w] = 1

        print(file)
        for k, v in counts.items():
            if v >= 2:
                print("{} appears {} times".format(k, v))

