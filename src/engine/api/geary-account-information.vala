/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A named signature that can be selected for an account or one of its aliases.
 */
public class Geary.AccountSignature : GLib.Object {

    public string name { get; set; default = ""; }
    public string html { get; set; default = ""; }

    public AccountSignature(string name, string html) {
        this.name = name;
        this.html = html;
    }

}


public class Geary.AccountInformation : BaseObject {


    public const int DEFAULT_PREFETCH_PERIOD_DAYS = 14;


    /** The next ordinal that should be allocated for an account. */
    public static int next_ordinal = 0;

    /** Comparator for account info objects based on their ordinals. */
    public static int compare_ascending(AccountInformation a, AccountInformation b) {
        int diff = a.ordinal - b.ordinal;
        if (diff != 0)
            return diff;

        // Stabilize on display name, which should always be unique.
        return a.display_name.collate(b.display_name);
    }


    /** A unique (engine-wide), opaque identifier for the account. */
    public string id { get; private set; }

    /** A unique (engine-wide) ordering for the account. */
    public int ordinal {
        get; set; default = AccountInformation.next_ordinal++;
    }

    /** Specifies the email provider for this account. */
    public Geary.ServiceProvider service_provider { get; private set; }

    /**
     * A human-readable label describing the email service provider.
     *
     * Known providers such as Gmail will have a label specified by
     * clients, but other accounts can only really be identified by
     * their server names. This attempts to extract a 'nice' value for
     * label based on the service's host names.
     */
    public string service_label {
        owned get {
            string? value = this._service_label;
            if (value == null) {
                string email_domain = this.primary_mailbox.domain;
                if (this.incoming.host.has_suffix(email_domain)) {
                    value = email_domain;
                } else {
                    string[] host_parts = this.incoming.host.split(".");
                    // If first part is an integer, looks like an ip so ignore it
                    if (host_parts.length > 2 && int.parse(host_parts[0]) == 0) {
                        host_parts = host_parts[1:host_parts.length];
                    }
                    value = string.joinv(".", host_parts);
                }
                // Don't stash the calculated value in _service_label
                // since we want it updated if the service host names
                // change
            }
            return value;
        }
        set { this._service_label = value; }
    }
    private string? _service_label = null;

    /**
     * A unique human-readable display name for this account.
     *
     * Use this to display a string to the user that can uniquely
     * identify this account. Note this value is mutable - it may
     * change as a result of user action, so do not rely on it staying
     * the same.
     */
    public string display_name {
        get {
            return (!String.is_empty_or_whitespace(this.label))
                ? this.label
                : this.primary_mailbox.address;
        }
    }

    /**
     * User-provided label for the account.
     *
     * This is not to be used in the UI (use `display_name` instead)
     * and not transmitted on the wire or used in correspondence.
     */
    public string label { get; set; default = ""; }

    /**
     * The default sender mailbox address for the account.
     *
     * This is the first mailbox in the {@link sender_mailboxes} list.
     */
    public Geary.RFC822.MailboxAddress primary_mailbox {
        owned get { return this.sender_mailboxes.get(0); }
    }

    /**
     * A read-only list of sender mailbox address for the account.
     *
     * The first address in the list is the default address, others
     * are essentially aliases.
     */
    public Gee.List<Geary.RFC822.MailboxAddress>? sender_mailboxes {
        owned get { return this.mailboxes.read_only_view; }
    }

    /** Determines if the account has more than one sender mailbox. */
    public bool has_sender_aliases {
        get { return this.sender_mailboxes.size > 1; }
    }

    /** Specifies the number of days to be fetched by the account sync. */
    public int prefetch_period_days {
        get; set; default = DEFAULT_PREFETCH_PERIOD_DAYS;
    }

    /** Specifies if sent email should be saved to the Sent folder. */
    public bool save_sent {
        get {
            bool save = _save_sent;
            switch (this.service_provider) {
            case GMAIL:
            case OUTLOOK:
                save = false;
                break;
            default:
                break;
            }
            return save;
        }
        set { this._save_sent = value; }
    }
    private bool _save_sent = true;

    /** Determines if drafts should be saved on the server. */
    public bool save_drafts { get; set; default = true; }

    /**
     * The source of authentication credentials for this account.
     */
    public CredentialsMediator mediator { get; private set; }

    /* Incoming email service configuration. */
    public ServiceInformation incoming { get; set; }

    /* Outgoing email service configuration. */
    public ServiceInformation outgoing { get; set; }

    /** A lock that can be used to ensure saving is serialised. */
    public Nonblocking.Mutex write_lock {
        get; private set; default = new Nonblocking.Mutex();
    }

    /** Specifies if an email sig should be appended to new messages. */
    public bool use_signature { get; set; default = false; }

    /** Specifies the email sig to be appended to new messages. */
    public string signature { get; set; default = ""; }

    /**
     * Named signatures available to this account.
     *
     * The legacy {@link signature} property remains the account's default
     * signature and is kept in sync with {@link default_signature_name}.
     */
    public Gee.List<AccountSignature> signatures {
        owned get { return this.signature_list.read_only_view; }
    }

    /** Name of the signature used when no alias-specific signature is set. */
    public string default_signature_name { get; set; default = ""; }

    /**
     * Alias address to signature name mappings.
     *
     * A missing address uses the account default. An empty name explicitly
     * disables a signature for that alias.
     */
    public Gee.Map<string,string> alias_signatures {
        get; private set;
        default = new Gee.HashMap<string,string>();
    }

    /**
     * Location of the account's config directory.
     *
     * This directory is used to store small, per-account
     * configuration files, including the account's settings key file.
     */
    public File? config_dir { get; private set; default = null; }

    /**
     * Location of the account's data directory.
     *
     * This directory is used to store large, per-account data files
     * such as the account database.
     */
    public File? data_dir { get; private set; default = null; }

    private Gee.Map<Folder.SpecialUse?,Gee.List<string>> special_use_paths =
        new Gee.HashMap<Folder.SpecialUse?,Gee.List<string>>(
            (k) => GLib.int_hash(k),
            (k1, k2) => (Folder.SpecialUse) k1 == (Folder.SpecialUse) k2
        );

    private Gee.ArrayList<AccountSignature> signature_list =
        new Gee.ArrayList<AccountSignature>();

    private Gee.List<Geary.RFC822.MailboxAddress> mailboxes {
        get; private set;
        default = new Gee.LinkedList<Geary.RFC822.MailboxAddress>();
    }


    /**
     * Emitted when a service has reported an authentication failure.
     *
     * No further connection attempts will be made after this signal
     * has been fired until the associated {@link ClientService} has
     * been restarted. It is up to the client to prompt the user for
     * updated credentials and restart the service.
     */
    public signal void authentication_failure(ServiceInformation service);

    /**
     * Emitted when an endpoint has reported TLS certificate warnings.
     *
     * This signal is emitted when either of the incoming or outgoing
     * endpoints emit the signal with the same name. It may be more
     * convenient for clients to connect to this instead.
     *
     * No further connection attempts will be made after this signal
     * has been fired until the associated {@link ClientService} has
     * been restarted. It is up to the client to prompt the user to
     * take action about the certificate (e.g. decide to pin it) then
     * restart the service.
     *
     * @see Endpoint.untrusted_host
     */
    public signal void untrusted_host(ServiceInformation service,
                                      Endpoint endpoint,
                                      GLib.TlsConnection cx);

    /** Emitted when the account settings have changed. */
    public signal void changed();

    /**
     * Creates a new account with default settings.
     */
    public AccountInformation(string id,
                              ServiceProvider provider,
                              CredentialsMediator mediator,
                              RFC822.MailboxAddress primary_mailbox) {
        this.id = id;
        this.mediator = mediator;
        this.service_provider = provider;
        this.incoming = new ServiceInformation(Protocol.IMAP, provider);
        this.outgoing = new ServiceInformation(Protocol.SMTP, provider);

        provider.set_account_defaults(this);

        append_sender(primary_mailbox);
    }

    /**
     * Creates a copy of an existing config.
     */
    public AccountInformation.copy(AccountInformation other) {
        this(
            other.id,
            other.service_provider,
            other.mediator,
            other.primary_mailbox
        );
        this.ordinal = other.ordinal;
        this.service_label = other.service_label;
        this.label = other.label;
        if (other.mailboxes.size > 1) {
            this.mailboxes.add_all(
                other.mailboxes.slice(1, other.mailboxes.size)
            );
        }
        this.prefetch_period_days = other.prefetch_period_days;
        this.save_sent = other.save_sent;
        this.save_drafts = other.save_drafts;
        this.use_signature = other.use_signature;
        this.signature = other.signature;
        this.default_signature_name = other.default_signature_name;
        foreach (AccountSignature signature in other.signatures) {
            this.signature_list.add(
                new AccountSignature(signature.name, signature.html)
            );
        }
        this.alias_signatures.set_all(other.alias_signatures);

        this.incoming = new ServiceInformation.copy(other.incoming);
        this.outgoing = new ServiceInformation.copy(other.outgoing);

        this.special_use_paths.set_all(other.special_use_paths);

        this.config_dir = other.config_dir;
        this.data_dir = other.data_dir;
    }

    /** Sets the location of the account's storage directories. */
    public void set_account_directories(GLib.File config, GLib.File data) {
        this.config_dir = config;
        this.data_dir = data;
    }

    /**
     * Determines if a mailbox is in the sender mailbox list.
     *
     * Returns true if the given address is equal to one of the
     * addresses in {@link sender_mailboxes}, by case-insensitive
     * matching the address parts.
     *
     * @see Geary.RFC822.MailboxAddress.equal_to
     */
    public bool has_sender_mailbox(Geary.RFC822.MailboxAddress email) {
        return this.mailboxes.any_match((alt) => alt.equal_to(email));
    }

    /**
     * Appends a mailbox to the list of sender mailboxes.
     *
     * Mailboxes with duplicate addresses will not be added.
     *
     * Returns true if the mailbox was appended.
     */
    public bool append_sender(Geary.RFC822.MailboxAddress mailbox) {
        bool add = !has_sender_mailbox(mailbox);
        if (add) {
            this.mailboxes.add(mailbox);
        }
        return add;
    }

    /**
     * Inserts a mailbox into the list of sender mailboxes.
     *
     * Mailboxes with duplicate addresses will not be added.
     *
     * Returns true if the mailbox was inserted.
     */
    public bool insert_sender(int index, Geary.RFC822.MailboxAddress mailbox) {
        bool add = !has_sender_mailbox(mailbox);
        if (add) {
            this.mailboxes.insert(index, mailbox);
        }
        return add;
    }

    /**
     * Removes a mailbox from the list of sender mailboxes.
     *
     * The last mailbox cannot be removed.
     *
     * Returns true if the mailbox was removed.
     */
    public bool remove_sender(Geary.RFC822.MailboxAddress mailbox) {
        bool removed = false;
        if (this.mailboxes.size > 1) {
            removed = this.mailboxes.remove(mailbox);
        }
        return removed;
    }

    /**
     * Replace a mailbox at the specified index.
     */
    public void replace_sender(int index, Geary.RFC822.MailboxAddress mailbox) {
        Geary.RFC822.MailboxAddress old = this.mailboxes.get(index);
        string? alias_signature = this.alias_signatures.get(
            old.address.down()
        );
        this.mailboxes.set(index, mailbox);
        this.alias_signatures.unset(old.address.down());
        if (alias_signature != null) {
            this.alias_signatures.set(
                mailbox.address.down(), alias_signature
            );
        }
    }

    /**
     * Finds a named signature, ignoring surrounding whitespace in its name.
     */
    public AccountSignature? find_signature(string name) {
        string wanted = name.strip();
        foreach (AccountSignature signature in this.signature_list) {
            if (signature.name.strip() == wanted) {
                return signature;
            }
        }
        return null;
    }

    /**
     * Adds a named signature, making the name unique if necessary.
     */
    public AccountSignature add_signature(string name, string html = "") {
        string unique = name.strip();
        if (unique == "") {
            unique = "Signature %d".printf(this.signature_list.size + 1);
        }
        string base_name = unique;
        int suffix = 2;
        while (find_signature(unique) != null) {
            unique = "%s %d".printf(base_name, suffix++);
        }
        var signature = new AccountSignature(unique, html);
        this.signature_list.add(signature);
        return signature;
    }

    /**
     * Updates the HTML of a named signature.
     */
    public bool set_signature_html(string name, string html) {
        AccountSignature? signature = find_signature(name);
        if (signature == null) {
            return false;
        }
        signature.html = html;
        sync_default_signature();
        return true;
    }

    /**
     * Selects the account default, or disables the default with null/empty.
     */
    public void set_default_signature(string? name) {
        this.default_signature_name = name?.strip() ?? "";
        sync_default_signature();
    }

    /**
     * Removes a named signature and any alias mappings that refer to it.
     */
    public bool remove_signature(string name) {
        AccountSignature? signature = find_signature(name);
        if (signature == null || this.signature_list.size <= 1) {
            return false;
        }

        string removed_name = signature.name;
        this.signature_list.remove(signature);
        if (this.default_signature_name.strip() == removed_name.strip()) {
            this.default_signature_name = "";
        }

        var stale = new Gee.ArrayList<string>();
        foreach (var entry in this.alias_signatures.entries) {
            if (entry.value.strip() == removed_name.strip()) {
                stale.add(entry.key);
            }
        }
        foreach (string address in stale) {
            this.alias_signatures.unset(address);
        }
        sync_default_signature();
        return true;
    }

    /**
     * Sets an alias-specific signature.
     *
     * A null name means the account default, while an empty name disables a
     * signature for this address.
     */
    public void set_alias_signature(string address,
                                    string? signature_name) {
        string key = address.down();
        if (signature_name == null) {
            this.alias_signatures.unset(key);
        } else {
            this.alias_signatures.set(key, signature_name.strip());
        }
    }

    /**
     * Returns the signature body for a sender address.
     */
    public string signature_for_mailbox(Geary.RFC822.MailboxAddress mailbox) {
        string address = mailbox.address.down();
        if (this.alias_signatures.has_key(address)) {
            string alias_name = this.alias_signatures.get(address) ?? "";
            if (alias_name == "") {
                return "";
            }
            AccountSignature? alias_signature = find_signature(alias_name);
            if (alias_signature != null) {
                return alias_signature.html;
            }
        }

        AccountSignature? default_signature =
            find_signature(this.default_signature_name);
        if (default_signature != null) {
            return default_signature.html;
        }

        // Configurations from before multiple signatures stored one signature
        // and a boolean saying whether it should be inserted.
        return this.use_signature ? this.signature : "";
    }

    /**
     * Returns the configured signature name for a sender address.
     *
     * Null means the legacy body-only signature is in use, while an empty
     * string explicitly means no signature.
     */
    public string? signature_name_for_mailbox(
        Geary.RFC822.MailboxAddress mailbox
    ) {
        string address = mailbox.address.down();
        if (this.alias_signatures.has_key(address)) {
            string alias_name = this.alias_signatures.get(address) ?? "";
            if (alias_name == "" || find_signature(alias_name) != null) {
                return alias_name;
            }
        }
        AccountSignature? default_signature =
            find_signature(this.default_signature_name);
        if (default_signature != null) {
            return default_signature.name;
        }
        return null;
    }

    private void sync_default_signature() {
        AccountSignature? signature =
            find_signature(this.default_signature_name);
        if (signature != null) {
            this.signature = signature.html;
            this.use_signature = true;
        } else {
            this.signature = "";
            this.use_signature = false;
        }
    }

    /**
     * Returns the folder path steps configured for a specific use.
     */
    public Gee.List<string> get_folder_steps_for_use(Folder.SpecialUse use) {
        var steps = this.special_use_paths.get(use);
        if (steps != null) {
            steps = steps.read_only_view;
        } else {
            steps = Gee.List.empty();
        }
        return steps;
    }

    /**
     * Sets the configured folder path steps for a specific use.
     */
    public void set_folder_steps_for_use(Folder.SpecialUse special,
                                         Gee.List<string>? new_path) {
        var existing = this.special_use_paths.get(special);
        if (new_path != null && !new_path.is_empty) {
            this.special_use_paths.set(special, new_path);
        } else {
            this.special_use_paths.unset(special);
        }
        if ((existing == null && new_path != null) ||
            (existing != null && new_path == null) ||
            (existing != null &&
             (existing.size != new_path.size ||
              existing.contains_all(new_path)))) {
            changed();
        }
    }

    /**
     * Returns a folder path based on the configured steps for a use.
     */
    public FolderPath? new_folder_path_for_use(FolderRoot root,
                                               Folder.SpecialUse use) {
        FolderPath? path = null;
        var steps = this.special_use_paths.get(use);
        if (steps != null) {
            path = root;
            foreach (string step in steps) {
                path = path.get_child(step);
            }
        }
        return path;
    }

    /**
     * Returns the configured special folder use for a given path.
     */
    public Folder.SpecialUse get_folder_use_for_path(FolderPath path) {
        var path_steps = path.as_array();
        var use = Folder.SpecialUse.NONE;
        foreach (var entry in this.special_use_paths.entries) {
            var use_steps = entry.value;
            var found = false;
            if (path_steps.length == use_steps.size) {
                found = true;
                for (int i = path_steps.length - 1; i >= 0; i--) {
                    if (path_steps[i] != use_steps[i]) {
                        found = false;
                        break;
                    }
                }
            }
            if (found) {
                use = entry.key;
                break;
            }
        }
        return use;
    }

    /**
     * Returns the best credentials to use for the outgoing service.
     *
     * This method checks for an outgoing service that use incoming
     * service's credentials for authentication and if enabled,
     * returns those. If this method returns null, then outgoing
     * authentication should not be attempted for this account.
     */
    public Credentials? get_outgoing_credentials() {
        Credentials? outgoing = null;
        switch (this.outgoing.credentials_requirement) {
        case USE_INCOMING:
            outgoing = this.incoming.credentials;
            break;
        case CUSTOM:
            outgoing = this.outgoing.credentials;
            break;
        case NONE:
            // no-op
            break;
        }
        return outgoing;
    }

    /**
     * Loads the authentication token for the outgoing service.
     *
     * Credentials are loaded from the mediator, thus it may yield for
     * some time.
     *
     * Returns true if the credential's token was successfully loaded
     * or are not needed (that is, if the credentials are null), or
     * false if the token could not be loaded and the service's
     * credentials are invalid.
     */
    public async bool load_outgoing_credentials(GLib.Cancellable? cancellable)
        throws GLib.Error {
        Credentials? creds = get_outgoing_credentials();
        bool loaded = true;
        if (creds != null) {
            if (this.outgoing.credentials_requirement == USE_INCOMING) {
                loaded = yield this.mediator.load_token(
                    this, this.incoming, cancellable
                );
            } else {
                loaded = yield this.mediator.load_token(
                    this, this.outgoing, cancellable
                );
            }
        }
        return loaded;
    }

    /**
     * Loads the authentication token for the incoming service.
     *
     * Credentials are loaded from the mediator, thus it may yield for
     * some time.
     *
     * Returns true if the credential's token was successfully loaded
     * or are not needed (that is, if the credentials are null), or
     * false if the token could not be loaded and the service's
     * credentials are invalid.
     */
    public async bool load_incoming_credentials(GLib.Cancellable? cancellable)
        throws GLib.Error {
        Credentials? creds = this.incoming.credentials;
        bool loaded = true;
        if (creds != null) {
            loaded = yield this.mediator.load_token(
                this, this.incoming, cancellable
            );
        }
        return loaded;
    }

    public bool equal_to(AccountInformation other) {
        return (
            this == other || (
                // This is probably overkill, but handy for testing.
                this.id == other.id &&
                this.ordinal == other.ordinal &&
                this.mediator == other.mediator &&
                this.service_provider == other.service_provider &&
                this.service_label == other.service_label &&
                this.label == other.label &&
                this.primary_mailbox.equal_to(other.primary_mailbox) &&
                this.sender_mailboxes.size == other.sender_mailboxes.size &&
                traverse(this.sender_mailboxes).all(
                    addr => other.sender_mailboxes.contains(addr)
                ) &&
                this.prefetch_period_days == other.prefetch_period_days &&
                this.save_sent == other.save_sent &&
                this.save_drafts == other.save_drafts &&
                this.use_signature == other.use_signature &&
                this.signature == other.signature &&
                this.default_signature_name == other.default_signature_name &&
                this.signatures.size == other.signatures.size &&
                traverse(this.signatures).all(
                    signature => {
                        AccountSignature? candidate =
                            other.find_signature(signature.name);
                        return candidate != null &&
                            candidate.html == signature.html;
                    }
                ) &&
                this.alias_signatures.size ==
                    other.alias_signatures.size &&
                this.alias_signatures.has_all(other.alias_signatures) &&
                this.incoming.equal_to(other.incoming) &&
                this.outgoing.equal_to(other.outgoing) &&
                this.special_use_paths.size == other.special_use_paths.size &&
                this.special_use_paths.has_all(other.special_use_paths) &&
                this.config_dir == other.config_dir &&
                this.data_dir == other.data_dir
            )
        );
    }

}
