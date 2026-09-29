bool startsSongRadioQueue({
  required String shelfId,
  required String shelfTitle,
}) {
  final title = shelfTitle.toLowerCase();
  return shelfId == 'quick-picks' ||
      shelfId.startsWith('personal-') ||
      const {'discover-7', 'discover-8', 'discover-11'}.contains(shelfId) ||
      title.contains('quick picks') ||
      title.contains('because you listened') ||
      title.contains('covers and remixes') ||
      title.contains('trending songs for you') ||
      title.contains('long listens');
}
