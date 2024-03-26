import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info/package_info.dart';
import 'package:sfmc/sfmc.dart';
import 'dart:math';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const HangmanApp());
}

class HangmanApp extends StatelessWidget {
  const HangmanApp({super.key});

  @override
  Widget build(BuildContext context) {
    SFMCSdk.enableLogging();
    return const MaterialApp(
      title: 'The Hanging Trees',
      home: SplashScreen(),
    );
  }
}

abstract class DatabaseHelper {
  Future<void> initializeDatabase();
  Future<void> insertWord(String word);
  Future<List<String>> loadWordList();
  Future<void> updateBestScore(String playerName, int score);
  Future<List<Map<String, dynamic>>> getBestScores();
  Future<void> removeScore(int id);
}

class SQLiteHelper extends DatabaseHelper {
  Database? _database;

  @override
  Future<void> initializeDatabase() async {
    _database = await openDatabase(
      join(await getDatabasesPath(), 'hangman_database.db'),
      onCreate: (db, version) {
        db.execute("CREATE TABLE words(id INTEGER PRIMARY KEY, word TEXT)");
        db.execute(
            "CREATE TABLE scores(id INTEGER PRIMARY KEY, name TEXT, score INTEGER)");
        // Populate with initial words. Replace this with your list of 1000 words.
        List<String> initialWords = [
          "ability", "able", "about", "above", "accept", "according", "account",
          "across", "act", //
          "action", "activity", "actually", "add", "address", "administration",
          "admit", "adult", //
          "affect", "after", "again", "against", "age", "agency", "agent",
          "ago", "agree", "agreement", //
          "ahead", "air", "all", "allow", "almost", "alone", "along", "already",
          "also", "although", //
          "always", "American", "among", "amount", "analysis", "and", "animal",
          "another", "answer", //
          "any", "anyone", "anything", "appear" //
        ];
        for (String word in initialWords) {
          db.insert('words', {'word': word});
        }
      },
      version: 1,
      password: 'your_strong_password',
    );
  }

  @override
  Future<void> insertWord(String word) async {
    await _database?.insert(
      'words',
      {'word': word},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<String>> loadWordList() async {
    final List<Map<String, dynamic>> maps = await _database!.query('words');
    return List.generate(maps.length, (i) {
      return maps[i]['word'];
    });
  }

  @override
  Future<void> updateBestScore(String playerName, int score) async {
    await _database!.insert(
      'scores',
      {'name': playerName, 'score': score},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getBestScores() async {
    await initializeDatabase(); // Ensure the database is initialized
    final List<Map<String, dynamic>> result = await _database!.query(
      'scores',
      orderBy: 'score ASC',
      limit: 10,
    );
    return result;
  }

  @override
  Future<void> removeScore(int id) async {
    await _database!.delete('scores', where: 'id=?', whereArgs: [id]);
  }
}

class HangmanGame extends StatefulWidget {
  const HangmanGame({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HangmanGameState createState() => _HangmanGameState();
}

class _HangmanGameState extends State<HangmanGame> {
  final DatabaseHelper databaseHelper = SQLiteHelper();

  String wordToGuess = '';
  List<String> guessedLetters = [];
  List<String> wordList = [];
  String playerName = '';
  int numberOfGuesses = 0;
  int incorrectGuesses = 0;
  final int maxGuesses = 6;
  int? bestScore;

  @override
  void initState() {
    super.initState();
    databaseHelper.initializeDatabase().then((_) {
      promptForName().then((_) {
        databaseHelper.loadWordList().then((loadedWordList) {
          setState(() {
            wordList = loadedWordList;
            wordToGuess = getRandomWord().toUpperCase();
          });
        });
      });
    });
  }

  Future<void> promptForName() async {
    playerName = await showDialog<String>(
          context: this.context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            TextEditingController _nameController = TextEditingController();
            return AlertDialog(
              title: const Text('Enter Your Name'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Name'),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[a-zA-Z ]')),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Start Game'),
                  onPressed: () {
                    // Use a GlobalKey to get the current state of the form and validate it
                    String enteredName = _nameController.text.trim();
                    if (enteredName.trim().isNotEmpty) {
                      Navigator.of(context)
                          .pop(enteredName); // Pass the entered name back
                    } else {
                      // Prompt the user to enter a name if the text field is empty
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a name.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        ) ??
        "";

    if (playerName.isEmpty) {
      await promptForName(); // Call recursively if the name is empty
    } else {
      setState(() {});
      SFMCSdk.setContactKey(playerName);
    }
  }

  String getRandomWord() {
    if (wordList.isEmpty) return '';
    final random = Random();
    int wordIndex = random.nextInt(wordList.length);
    return wordList[wordIndex];
  }

  void guessLetter(String letter) {
    setState(() {
      numberOfGuesses++;
      guessedLetters.add(letter.toUpperCase());
      if (!wordToGuess.contains(letter.toUpperCase())) {
        incorrectGuesses++;
      }
    });

    if (incorrectGuesses >= maxGuesses) {
      SFMCSdk.setAttribute("LastGameResult", "Loser");
      showLoserMessage(guesses: numberOfGuesses);
    }

    // Check if the game is over and if the player has won
    if (!getDisplayedWord().contains('_')) {
      SFMCSdk.setAttribute("LastGameResult", "Winner");
      updateBestScore();
    }
  }

  void updateBestScore() async {
    List<Map<String, dynamic>> bestScores =
        await databaseHelper.getBestScores();

    if (bestScores.length < 10 ||
        (bestScores.last['score'] as int) > incorrectGuesses) {
      await databaseHelper
          .updateBestScore(playerName, incorrectGuesses)
          .then((value) => showWinnerMessage(isNewBestScore: true));
    } else {
      showWinnerMessage(isNewBestScore: false);
    }

    if (bestScores.length >= 10) {
      await databaseHelper.removeScore(bestScores.last['id']);
    }
  }

  void showWinnerMessage({required bool isNewBestScore}) {
    String message = "Winner! You've guessed the word correctly.";
    SFMCSdk.trackEvent(CustomEvent("Purchase", attributes: {"Total": 1234}));
    if (isNewBestScore) {
      message += "\nNew Best Score: $incorrectGuesses!";
    }

    showDialog(
      context: this.context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Congratulations!"),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text("Play Again"),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                resetGame(); // Reset the game
              },
            ),
          ],
        );
      },
    );
  }

  void showLoserMessage({required int guesses}) {
    String message =
        "You lose! You made a total of $guesses guesses with $incorrectGuesses being incorrect.";

    showDialog(
      context: this.context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Sorry!"),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text("Play Again"),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                resetGame(); // Reset the game
              },
            ),
          ],
        );
      },
    );
  }

  void resetGame() {
    setState(() {
      wordToGuess = getRandomWord().toUpperCase();
      guessedLetters.clear();
      numberOfGuesses = 0;
      incorrectGuesses = 0;
      // Optionally, you can also load a new word list or do additional setup here.
    });
  }

  String getDisplayedWord() {
    String displayedWord = '';
    for (int i = 0; i < wordToGuess.length; i++) {
      if (guessedLetters.contains(wordToGuess[i])) {
        displayedWord += '${wordToGuess[i]} ';
      } else {
        displayedWord += '_ ';
      }
    }
    return displayedWord;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hangman Game - Hello, $playerName'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
                "assets/images/background.png"), // Replace with your actual image path
            fit: BoxFit.cover, // Ensures the image covers the whole screen
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              HangmanImage(incorrectGuesses),
              Text(
                getDisplayedWord(),
                style: const TextStyle(fontSize: 24),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (bestScore != null) Text('Best Score: $bestScore'),
              const SizedBox(height: 20),
              Keyboard(
                guessedLetters: guessedLetters.toSet(),
                onLetterPressed: guessLetter,
              ),
              ElevatedButton(
                onPressed: endGame,
                child: const Text('End Game'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void endGame() {
    // You might want to perform any cleanup here if necessary
    Navigator.pushAndRemoveUntil(
      this.context,
      MaterialPageRoute(builder: (context) => const SplashScreen()),
      (Route<dynamic> route) =>
          false, // This will remove all the routes below the splash screen
    );
  }
}

class Keyboard extends StatelessWidget {
  final Set<String> guessedLetters;
  final Function(String) onLetterPressed;

  Keyboard(
      {super.key, required this.guessedLetters, required this.onLetterPressed});

  final List<String> row1 = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
  final List<String> row2 = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
  final List<String> row3 = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        buildKeyboardRow(row1),
        buildKeyboardRow(row2),
        buildKeyboardRow(row3),
        // ... Include other widgets if necessary
      ],
    );
  }

  Widget buildKeyboardRow(List<String> letters) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: letters
          .map((letter) => Flexible(
                child: KeyboardButton(
                  letter: letter,
                  onPressed: onLetterPressed,
                  guessedLetters: guessedLetters,
                ),
              ))
          .toList(),
    );
  }
}

class KeyboardButton extends StatelessWidget {
  final String letter;
  final Function(String) onPressed;
  final Set<String> guessedLetters;

  const KeyboardButton(
      {super.key,
      required this.letter,
      required this.onPressed,
      required this.guessedLetters});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1.0), // Minimal padding around buttons
      child: ElevatedButton(
        onPressed:
            guessedLetters.contains(letter) ? null : () => onPressed(letter),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor:
              guessedLetters.contains(letter) ? Colors.grey : Colors.blue,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  4)), // Padding is set to zero for maximum space utilization
          padding: EdgeInsets.zero,
        ),
        child: Text(letter, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

class HangmanImage extends StatelessWidget {
  final int incorrectGuesses;

  const HangmanImage(this.incorrectGuesses, {super.key});

  @override
  Widget build(BuildContext context) {
    String imageName =
        'assets/images/hangman$incorrectGuesses.png'; // Your images should be named accordingly
    return Image.asset(
      imageName,
      height: 200, // Set the height as needed
    );
  }
}

class BestScoresScreen extends StatelessWidget {
  const BestScoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DatabaseHelper databaseHelper = SQLiteHelper();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Best Scores'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
                "assets/images/background.png"), // Replace with your image path
            fit: BoxFit.cover,
          ),
        ),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: databaseHelper.getBestScores(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No Best Scores yet.'));
            } else {
              final scores = snapshot.data!;
              return ListView.builder(
                itemCount: scores.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(
                      scores[index]['name'],
                      style: TextStyle(
                        fontSize: 20, // Adjust the font size as needed
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent[200], // Light red color
                      ),
                    ),
                    trailing: Text(
                      scores[index]['score'].toString(),
                      style: TextStyle(
                        fontSize: 20, // Adjust the font size as needed
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent[200], // Light red color
                      ),
                    ),
                  );
                },
              );
            }
          },
        ),
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity, // Ensure it fills the width of the screen
        height: double.infinity, // Ensure it fills the height of the screen
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/splash.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const HangmanGame()),
                  );
                },
                child: const Text('Play Game'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const BestScoresScreen()),
                  );
                },
                child: const Text('Best Scores'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SettingsScreen()),
                  );
                },
                child: const Text('Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotificationsEnabled = false;
  bool _analyticsCollectionEnabled = true;
  bool _loggingEnabled = true;
  String? _versionNumber;

  @override
  void initState() {
    super.initState();
    _getVersionNumber();
    _checkNotificationPermission();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        // You can also style the AppBar here if you like
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/splash.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 100), // You can adjust this value as needed
            SwitchListTile(
              title: const Text('Push Notifications'),
              value: _pushNotificationsEnabled,
              onChanged: (bool value) {
                setState(() {
                  _pushNotificationsEnabled = value;
                });
                _togglePushNotifications(value);
              },
            ),
            SwitchListTile(
              title: const Text('Analytics Collection'),
              value: _analyticsCollectionEnabled,
              onChanged: (bool value) {
                setState(() {
                  _analyticsCollectionEnabled = value;
                });
                SFMCSdk.setAnalyticsEnabled(value);
              },
            ),
            SwitchListTile(
              title: const Text('Enable Logging'),
              value: _loggingEnabled,
              onChanged: (bool value) {
                setState(() {
                  _loggingEnabled = value;
                });
                if (value) {
                  SFMCSdk.enableLogging();
                } else {
                  SFMCSdk.disableLogging();
                }
              },
            ),
            ElevatedButton(
              onPressed: () {
                // Call SFMC SDK method to log SDK state
                SFMCSdk.logSdkState();
              },
              child: const Text('Log SDK State'),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Version $_versionNumber', // Implement _getVersionNumber to retrieve version number
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _getVersionNumber() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _versionNumber = "${info.version} : ${info.buildNumber}";
    });
  }

  void _checkNotificationPermission() async {
    PermissionStatus status = await Permission.notification.request();
    if (status.isPermanentlyDenied) {
      openAppSettings().then((value) => setState(() {
            _updateScreenToggle(value);
          }));
    } else {
      _updateScreenToggle(status.isGranted);
    }
  }

  void _togglePushNotifications(bool value) async {
    if (value) {
      _checkNotificationPermission();
      SFMCSdk.enablePush();
    } else {
      _updateScreenToggle(false);
      SFMCSdk.disablePush();
    }
  }

  void _updateScreenToggle(bool value) {
    setState(() {
      _pushNotificationsEnabled = value;
    });
  }
}
