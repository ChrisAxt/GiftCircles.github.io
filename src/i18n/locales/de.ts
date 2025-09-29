const de = {
  translation: {
    titles: {
      event: 'Eventdetails',
      createEvent: 'Event erstellen',
      joinEvent: 'Event beitreten',
      editEvent: 'Event bearbeiten',
      list: 'Listen',
      addItem: 'Artikel hinzufügen',
      createList: 'Liste erstellen',
    },

    profile: {
      title: 'Profil',
      email: 'E-Mail',
      displayName: 'Anzeigename',
      saveName: 'Name speichern',
      memberSince: 'Mitglied seit',
      stats: { events: 'Events', listsCreated: 'Erstellte Listen' },
      account: 'Konto',
      signOut: 'Abmelden',
      dangerTitle: 'Gefahrenzone',
      dangerDesc: 'Dies löscht dein Profil dauerhaft und entfernt dich aus Events.',
      delete: 'Konto löschen',
      alerts: {
        nameRequiredTitle: 'Name erforderlich',
        nameRequiredBody: 'Bitte gib einen Anzeigenamen ein.',
        saveOkTitle: 'Gespeichert',
        saveOkBody: 'Dein Anzeigename wurde aktualisiert.',
        saveErrTitle: 'Speichern fehlgeschlagen',
        signOutErrTitle: 'Abmelden fehlgeschlagen',
        deleteConfirmTitle: 'Konto wirklich löschen?',
        deleteConfirmBody: 'Dadurch werden dein Profil und Mitgliedschaften dauerhaft gelöscht und du wirst abgemeldet.',
        cancel: 'Abbrechen',
        confirmDelete: 'Löschen',
        deleteErrTitle: 'Löschen fehlgeschlagen',
        deleteOkTitle: 'Konto gelöscht',
        deleteOkBody: 'Dein Konto wurde entfernt.',
      },
      settings: { title: 'Einstellungen', appearance: 'Darstellung', language: 'Sprache', push: 'Push-Mitteilungen' },
      common: { system: 'System', light: 'Hell', dark: 'Dunkel', english: 'Englisch', swedish: 'Schwedisch' },
    },

    navigation: {
      tabs: {
        events: 'Events',
        lists: 'Listen',
        claimed: 'Reserviert',
        profile: 'Profil',
      },
    },

    eventList: {
      header: {
        welcome: 'Willkommen zurück,',
        tagline: 'Geschenke einfach koordinieren',
        emptyName: 'du',
      },
      stats: {
        activeEvents: 'Aktive Events',
        itemsClaimed: 'Reservierte Artikel',
        toPurchase: 'Noch Zu Kaufen',
      },
      title: 'Deine Events',
      toolbar: { create: 'Erstellen', join: 'Beitreten' },

      empty: {
        title: 'Noch keine Events.',
        body: 'Erstelle dein erstes Event oder tritt mit einem Code bei.',
        create: 'Event erstellen',
        join: 'Mit Code beitreten',
      },

      eventCard: {
        members_one: '{{count}} Mitglied',
        members_other: '{{count}} Mitglieder',
        claimedShort: '{{claimed}}/{{total}} reserviert',
        today: 'heute',
        tomorrow: 'morgen',
        inDays_one: 'in {{count}} Tag',
        inDays_other: 'in {{count}} Tagen',
        daysAgo_one: 'vor {{count}} Tag',
        daysAgo_other: 'vor {{count}} Tagen',
        noDate: 'Kein Datum',
      },

      actions: { share: 'Teilen', edit: 'Bearbeiten', delete: 'Löschen', leave: 'Verlassen' },

      alerts: {
        deleteTitle: 'Event löschen?',
        deleteBody: 'Dies entfernt alle Listen, Artikel und Reservierungen für alle.',
        leaveTitle: 'Event verlassen?',
        leaveBody: 'Du wirst aus diesem Event entfernt und deine Reservierungen werden gelöscht.',
        cancel: 'Abbrechen',
        confirmDelete: 'Löschen',
        confirmLeave: 'Verlassen',
      },

      errors: {
        loadFailed: 'Events konnten nicht geladen werden',
        generic: 'Etwas ist schiefgelaufen',
      },
    },

    eventDetail: {
      header: {
        adminNote: 'Du bist Admin dieses Events.',
        memberNote: 'Mitgliedszugriff',
      },
      stats: {
        members: 'Mitglieder',
        items: 'Artikel',
        claimed: 'Reserviert',
      },
      toolbar: {
        edit: 'Bearbeiten',
        delete: 'Löschen',
      },
      actions: {
        share: 'Teilen',
        leave: 'Verlassen',
        createList: 'Liste erstellen',
      },
      members: {
        title: 'Mitglieder',
        show: 'Anzeigen',
        hide: 'Ausblenden',
        remove: 'Entfernen',
        roles: {
          giver: 'Schenker',
          recipient: 'Beschenkter',
          admin: 'Admin',
        },
      },
      lists: {
        title: 'Listen',
        emptyTitle: 'Noch keine Listen.',
        emptyBody: 'Erstelle eine, um zu starten.',
      },
      invite: {
        title: 'Einladungsoptionen',
        emailLabel: 'E-Mail senden',
        emailPlaceholder: 'name@example.com',
        cancel: 'Abbrechen',
        sendEmail: 'E-Mail senden',
        sending: 'Senden…',
        sendCode: 'Code senden',
        sentTitle: 'Einladung gesendet',
        sentBody: 'Wir haben deine Einladung per E-Mail verschickt.',
        missingEmailTitle: 'E-Mail fehlt',
        missingEmailBody: 'Bitte gib eine E-Mail-Adresse ein.',
        sendFailedTitle: 'Senden fehlgeschlagen',
      },
      share: {
        joinWithCode: 'Tritt meinem Event „{{title}}“ bei: Code {{code}}',
      },
      alerts: {
        notAllowedTitle: 'Nicht erlaubt',
        onlyAdminDelete: 'Nur ein Admin kann dieses Event löschen.',
        deleteTitle: 'Event löschen?',
        deleteBody: 'Dies entfernt alle Listen, Artikel und Reservierungen für alle.',
        cancel: 'Abbrechen',
        confirmDelete: 'Löschen',

        loadErrorTitle: 'Ladefehler',

        removeMemberTitle: 'Mitglied entfernen?',
        removeMemberBody: 'Die Person wird entfernt und ihre Reservierungen gelöscht.',
        removeFailed: 'Entfernen fehlgeschlagen',
        alreadyRemoved: 'Bereits entfernt',
        memberRemoved: 'Mitglied entfernt',

        leaveTitle: 'Event verlassen?',
        leaveBody: 'Du wirst aus diesem Event entfernt und deine Reservierungen werden gelöscht.',
        notMember: 'Kein Mitglied',
        leaveFailed: 'Verlassen fehlgeschlagen',
        leftEvent: 'Event verlassen',
      },
    },

    editEvent: {
      title: 'Event bearbeiten',
      labels: {
        title: 'Titel',
        date: 'Datum',
        joinCode: 'Beitrittscode',
      },
      placeholders: {
        title: 'z. B. Bobs Geburtstag',
        date: 'JJJJ-MM-TT',
        selectDate: 'Datum wählen',
      },
      actions: {
        retry: 'Erneut versuchen',
        back: 'Zurück',
        copy: 'Kopieren',
        save: 'Änderungen speichern',
      },
      states: {
        viewOnly: 'Nur Ansicht (kein Admin)',
        saving: 'Speichern…',
      },
      messages: {
        signInRequired: 'Anmeldung erforderlich.',
        notAllowed: 'Nicht erlaubt',
        onlyAdmins: 'Nur Event-Admins können bearbeiten.',
        titleRequired: 'Titel erforderlich',
        enterTitle: 'Bitte gib einen Titel ein.',
        eventUnavailable: 'Event nicht verfügbar.',
        copied: 'Beitrittscode kopiert',
        copyFailed: 'Kopieren fehlgeschlagen',
        updated: 'Event aktualisiert',
        saveFailed: 'Speichern fehlgeschlagen',
        failedToLoad: 'Event konnte nicht geladen werden.',
        notFound: 'Event nicht gefunden oder keine Berechtigung.',
      },
    },

    createList: {
      title: 'Liste erstellen',
      labels: {
        listName: 'Listenname',
      },
      placeholders: {
        listName: 'z. B. Geschenke für Bob',
      },
      sections: {
        recipients: {
          title: 'Empfänger (für wen diese Liste ist)',
          help: 'Tippe, um einen oder mehrere Empfänger auszuwählen.',
        },
        visibility: {
          title: 'Sichtbarkeit',
          help: 'Wähle, wer diese Liste sehen kann.',
        },
        exclusions: {
          title: 'Wen ausschließen',
          help: 'Ausgewählte Personen sehen diese Liste nicht (auch wenn sie Empfänger sind).',
        },
      },
      visibility: {
        public: 'Für alle sichtbar',
        exclude: 'Bestimmte Personen ausschließen',
      },
      actions: {
        create: 'Liste erstellen',
      },
      states: {
        creating: 'Wird erstellt…',
      },
      toasts: {
        loadError: 'Ladefehler',
        notSignedIn: 'Nicht angemeldet',
        listNameRequired: 'Listenname erforderlich',
        recipientsRequired: {
          title: 'Empfänger erforderlich',
          body: 'Wähle mindestens einen Empfänger.',
        },
        createFailed: {
          title: 'Erstellen fehlgeschlagen',
          noId: 'Keine Listen-ID zurückgegeben.',
        },
        notMember: 'Du bist kein Mitglied dieses Events.',
        created: {
          title: 'Liste erstellt',
          body: 'Deine Liste wurde erfolgreich erstellt.',
        },
      },
      user: 'Nutzer {{id}}',
    },

    addItem: {
      title: 'Artikel hinzufügen',
      labels: {
        name: 'Artikelname',
        urlOpt: 'URL (optional)',
        priceOpt: 'Preis (optional)',
        notesOpt: 'Notizen (optional)',
      },
      placeholders: {
        name: 'z. B. Noise-Cancelling-Kopfhörer',
        url: 'z. B. https://example.com/produkt',
        price: 'z. B. 149.99',
        notes: 'z. B. Bevorzugt Over-Ear',
      },
      actions: {
        add: 'Hinzufügen',
      },
      states: {
        adding: 'Wird hinzugefügt…',
      },
      toasts: {
        itemNameRequired: { title: 'Artikelname erforderlich', body: 'Bitte gib einen Namen ein.' },
        invalidPrice:     { title: 'Ungültiger Preis',         body: 'Gib eine Zahl wie 19.99 ein' },
        notSignedIn: 'Nicht angemeldet',
        added: 'Artikel hinzugefügt',
        addFailed: { title: 'Hinzufügen fehlgeschlagen' },
      },
      errors: {
        generic: 'Fehler',
      },
    },

    listDetail: {
      title: 'Liste',
      actions: {
        addItem: 'Artikel hinzufügen',
        delete: 'Löschen',
      },
      empty: 'Noch keine Artikel.',
      summary: {
        label: 'Reserviert: {{claimed}} · Nicht reserviert: {{unclaimed}}',
      },
      item: {
        notClaimed: 'Noch nicht reserviert',
        claimedByYou: 'Reserviert von: Dir',
        claimedByName: 'Reserviert von: {{name}}',
        hiddenForRecipients: 'Käufer bleiben für Empfänger verborgen.',
        someone: 'Jemand',
      },
      confirm: {
        deleteItemTitle: 'Artikel löschen?',
        deleteItemBody: 'Dadurch werden „{{name}}“ und alle Reservierungen entfernt.',
        deleteListTitle: 'Liste löschen?',
        deleteListBody: 'Dadurch werden die Liste und alle Artikel sowie Reservierungen entfernt. Dies kann nicht rückgängig gemacht werden.',
      },
      errors: {
        generic: 'Fehler',
        load: 'Beim Laden dieser Liste ist ein Fehler aufgetreten.',
        notFound: 'Diese Liste existiert nicht oder du hast keinen Zugriff.',
        notAllowed: 'Nicht erlaubt',
        cannotDeleteBody: 'Du kannst diesen Artikel nicht löschen.',
        hasClaimsTitle: 'Löschen nicht möglich',
        hasClaimsBody: 'Erst Reservierung aufheben oder Admin/Listen-Owner fragen.',
        alreadyGoneTitle: 'Schon entfernt',
        alreadyGoneBody: 'Diesen Artikel gibt es nicht mehr.',
        deleteFailed: 'Löschen fehlgeschlagen',
        directDeleteBlocked: 'Direktes Löschen blockiert',
        goBack: 'Zurück',
      },
    },

    allLists: {
      title: 'Alle Listen',
      eventLabel: 'Event: {{title}}',
      event: 'Event',
      empty: 'Noch keine sichtbaren Listen.',
    },

    myClaims: {
      title: 'Meine reservierten Artikel',
      line: '{{event}} · {{list}}',
      markPurchased: 'Als gekauft markieren',
      markNotPurchased: 'Als nicht gekauft markieren',
      empty: 'Du hast noch nichts reserviert.',
      updateFailed: 'Aktualisierung fehlgeschlagen',
      fallbackItem: 'Artikel',
      fallbackList: 'Liste',
      fallbackEvent: 'Event',
    },

    createEvent: {
      titleLabel: 'Titel',
      titlePlaceholder: 'z. B. Bobs Geburtstag',
      descriptionLabel: 'Beschreibung (optional)',
      descriptionPlaceholder: 'z. B. Ort, Thema, Notizen…',
      dateLabel: 'Eventdatum (optional)',
      datePlaceholder: 'Datum wählen',
      done: 'Fertig',
      recursLabel: 'Wiederholt sich',
      recurs: { none: 'Keine', weekly: 'Wöchentlich', monthly: 'Monatlich', yearly: 'Jährlich' },
      create: 'Erstellen',
      creating: 'Wird erstellt…',
      toastMissingTitleTitle: 'Titel fehlt',
      toastMissingTitleBody: 'Bitte gib einen Eventtitel ein.',
      toastCreated: 'Event erstellt',
      toastCreateFailed: 'Erstellen fehlgeschlagen',
    },

    joinEvent: {
      heading: 'Event beitreten',
      codeLabel: 'Beitrittscode eingeben',
      codePlaceholder: 'z. B. 7G4K-MQ',
      join: 'Beitreten',
      joining: 'Beitritt…',
      alertEnterTitle: 'Code eingeben',
      alertEnterBody: 'Füge den Beitrittscode ein.',
      alertInvalidTitle: 'Ungültiger Code',
      alertInvalidBody: 'Dieser Beitrittscode wurde nicht gefunden.',
      alertFailedTitle: 'Beitritt fehlgeschlagen',
    },
  },
};

export default de;
