class PromptPayAccount {
  const PromptPayAccount({this.phone})
    : usesNationalId = false,
      nationalIdLastFour = null;

  const PromptPayAccount.nationalId([this.nationalIdLastFour])
    : usesNationalId = true,
      phone = null;

  final bool usesNationalId;
  final String? phone;
  final String? nationalIdLastFour;
}
