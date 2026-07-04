#import <Cocoa/Cocoa.h>

@interface Document : NSDocument

// Déclaration de la propriété pour l'éditeur de texte
@property (unsafe_unretained) IBOutlet NSTextView *ruleTextView;

// Déclaration de l'action du bouton de compilation
- (IBAction)compileRule:(id)sender;

// Export de N secondes de simulation en fichier vidéo (.mp4).
// À câbler dans MainMenu.xib sur un item de menu (ex: File > "Exporter en vidéo…").
- (IBAction)exportVideo:(id)sender;

@end
