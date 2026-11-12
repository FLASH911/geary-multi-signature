/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.AccountInformationTest : TestCase {


    public AccountInformationTest() {
        base("Geary.AccountInformationTest");
        add_test("test_save_sent_defaults", test_save_sent_defaults);
        add_test("test_sender_mailboxes", test_sender_mailboxes);
        add_test("test_service_label", test_service_label);
        add_test("signatures_for_aliases", signatures_for_aliases);
        add_test("folder_steps_accessors", folder_steps_accessors);
    }

    public void test_save_sent_defaults() throws GLib.Error {
        assert_true(
            new AccountInformation(
                "test",
                ServiceProvider.OTHER,
                new Mock.CredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
        assert_false(
            new AccountInformation(
                "test",
                ServiceProvider.GMAIL,
                new Mock.CredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
        assert_false(
            new AccountInformation(
                "test",
                ServiceProvider.OUTLOOK,
                new Mock.CredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
    }

    public void test_sender_mailboxes() throws GLib.Error {
        AccountInformation test = new AccountInformation(
            "test",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new RFC822.MailboxAddress(null, "test1@example.com")
        );

        assert_true(test.primary_mailbox.equal_to(
                        new RFC822.MailboxAddress(null, "test1@example.com")));
        assert_false(test.has_sender_aliases);

        test.append_sender(new RFC822.MailboxAddress(null, "test2@example.com"));
        assert_true(test.has_sender_aliases);

        test.append_sender(new RFC822.MailboxAddress(null, "test3@example.com"));
        assert_true(test.has_sender_aliases);

        assert_true(
            test.has_sender_mailbox(new RFC822.MailboxAddress(null, "test1@example.com")),
            "Primary address not found"
        );
        assert_true(
            test.has_sender_mailbox(new RFC822.MailboxAddress(null, "test2@example.com")),
            "First alt address not found"
        );
        assert_true(
            test.has_sender_mailbox(new RFC822.MailboxAddress(null, "test3@example.com")),
            "Second alt address not found"
        );
        assert_false(
            test.has_sender_mailbox(new RFC822.MailboxAddress(null, "unknowne@example.com")),
            "Unknown address found"
        );
    }

    public void test_service_label() throws GLib.Error {
        AccountInformation test = new_information();
        assert_equal(test.service_label, "");

        test = new_information();
        test.incoming.host = "example.com";
        assert_equal(test.service_label, "example.com");

        test = new_information();
        test.incoming.host = "test.example.com";
        assert_equal(test.service_label, "example.com");

        test = new_information();
        test.incoming.host = "other.com";
        test.outgoing.host = "other.com";
        assert_equal(test.service_label, "other.com");

        test = new_information();
        test.incoming.host = "mail.other.com";
        test.outgoing.host = "mail.other.com";
        assert_equal(test.service_label, "other.com");

        test = new_information();
        test.incoming.host = "imap.other.com";
        test.outgoing.host = "smtp.other.com";
        assert_equal(test.service_label, "other.com");

        test = new_information();
        test.incoming.host = "not-mail.other.com";
        test.outgoing.host = "not-mail.other.com";
        assert_equal(test.service_label, "other.com");
    }

    public void signatures_for_aliases() throws GLib.Error {
        AccountInformation test = new_information();
        var work = test.add_signature("Work", "<p>Work sig</p>");
        var personal = test.add_signature("Personal", "<p>Personal sig</p>");
        assert_equal(work.name, "Work");
        assert_equal(personal.name, "Personal");
        assert_equal(test.add_signature("Work").name, "Work 2");

        test.set_default_signature(work.name);
        assert_true(test.use_signature, "Default enables signatures");
        assert_equal(test.signature, work.html);
        assert_equal(
            test.signature_name_for_mailbox(test.primary_mailbox),
            work.name
        );

        var alias = new RFC822.MailboxAddress(
            "Work Alias", "alias@example.com"
        );
        test.append_sender(alias);
        assert_equal(test.signature_for_mailbox(alias), work.html);

        test.set_alias_signature(alias.address, personal.name);
        assert_equal(test.signature_for_mailbox(alias), personal.html);
        assert_equal(
            test.signature_name_for_mailbox(alias), personal.name
        );

        test.set_alias_signature(alias.address, "");
        assert_equal(test.signature_for_mailbox(alias), "");
        assert_equal(test.signature_name_for_mailbox(alias), "");

        test.set_default_signature(null);
        assert_equal(test.signature_for_mailbox(test.primary_mailbox), "");
        test.set_alias_signature(alias.address, personal.name);
        assert_equal(test.signature_for_mailbox(alias), personal.html);

        test.set_default_signature(work.name);
        test.set_alias_signature(alias.address, null);
        assert_equal(test.signature_for_mailbox(alias), work.html);

        AccountInformation copy = new AccountInformation.copy(test);
        var copied_work = copy.find_signature("Work");
        assert_true(
            copied_work != null && copied_work.html == work.html,
            "Signature body copied"
        );
        assert_equal(
            copy.default_signature_name, test.default_signature_name
        );
        copy.set_alias_signature(alias.address, personal.name);
        assert_equal(copy.signature_for_mailbox(alias), personal.html);
        assert_equal(test.signature_for_mailbox(alias), work.html);
    }

    public void folder_steps_accessors() throws GLib.Error {
        AccountInformation test = new_information();

        assert_collection(test.get_folder_steps_for_use(NONE)).is_empty();
        assert_collection(test.get_folder_steps_for_use(ARCHIVE)).is_empty();
        assert_collection(test.get_folder_steps_for_use(JUNK)).is_empty();

        var archive = new Gee.ArrayList<string>.wrap({"Archive"});
        test.set_folder_steps_for_use(ARCHIVE, archive);
        assert_collection(test.get_folder_steps_for_use(ARCHIVE))
        .is_non_empty()
        .contains("Archive");

        var junk = new Gee.ArrayList<string>.wrap({"Junk"});
        test.set_folder_steps_for_use(JUNK, junk);
        assert_collection(test.get_folder_steps_for_use(ARCHIVE))
        .is_non_empty()
        .contains("Archive");
        assert_collection(test.get_folder_steps_for_use(JUNK))
        .is_non_empty()
        .contains("Junk");
    }

    private AccountInformation new_information(ServiceProvider provider =
                                               ServiceProvider.OTHER) {
        return new AccountInformation(
            "test",
            provider,
            new Mock.CredentialsMediator(),
            new RFC822.MailboxAddress(null, "test1@example.com")
        );
    }

}
