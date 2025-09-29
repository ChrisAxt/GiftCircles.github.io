// src/i18n/it.ts
const it = {
  translation: {
    languages: {
      nativeNames: { it: 'Italiano' },
    },

    titles: {
      event: 'Dettagli dell\'event',
      createEvent: 'Crea event',
      joinEvent: 'Unisciti all\'event',
      editEvent: 'Modifica event',
      list: 'Liste',
      addItem: 'Aggiungi articolo',
      createList: 'Crea lista',
    },

    profile: {
      title: 'Profilo',
      email: 'Email',
      displayName: 'Nome visualizzato',
      saveName: 'Salva nome',
      memberSince: 'Membro dal',
      stats: { events: 'Eventi', listsCreated: 'Liste create' },
      account: 'Account',
      signOut: 'Esci',
      dangerTitle: 'Zona pericolosa',
      dangerDesc: 'Questo eliminerà definitivamente il tuo profilo e ti rimuoverà dagli eventi.',
      delete: 'Elimina account',
      alerts: {
        nameRequiredTitle: 'Nome richiesto',
        nameRequiredBody: 'Inserisci un nome visualizzato.',
        saveOkTitle: 'Salvato',
        saveOkBody: 'Il tuo nome visualizzato è stato aggiornato.',
        saveErrTitle: 'Salvataggio non riuscito',
        signOutErrTitle: 'Uscita non riuscita',
        deleteConfirmTitle: 'Eliminare il tuo account?',
        deleteConfirmBody: 'Questo eliminerà il tuo profilo, le tue iscrizioni e ti disconnetterà.',
        cancel: 'Annulla',
        confirmDelete: 'Elimina',
        deleteErrTitle: 'Eliminazione non riuscita',
        deleteOkTitle: 'Account eliminato',
        deleteOkBody: 'Il tuo account è stato rimosso.',
      },
      settings: { title: 'Impostazioni', appearance: 'Aspetto', language: 'Lingua', push: 'Notifiche push' },
      common: { system: 'Sistema', light: 'Chiaro', dark: 'Scuro', english: 'Inglese', swedish: 'Svedese' },
    },

    navigation: {
      tabs: {
        events: 'Eventi',
        lists: 'Liste',
        claimed: 'Riservati',
        profile: 'Profilo',
      },
    },

    eventList: {
      header: {
        welcome: 'Bentornato/a,',
        tagline: 'Coordina i regali con facilità',
        emptyName: 'tu',
      },
      stats: {
        activeEvents: 'Eventi attivi',
        itemsClaimed: 'Articoli riservati',
        toPurchase: 'Da acquistare',
      },
      title: 'I tuoi eventi',
      toolbar: { create: 'Crea', join: 'Unisciti' },

      empty: {
        title: 'Nessun event ancora.',
        body: 'Crea il tuo primo event o unisciti con un codice.',
        create: 'Crea event',
        join: 'Unisciti con codice',
      },

      eventCard: {
        members_one: '{{count}} membro',
        members_other: '{{count}} membri',
        claimedShort: '{{claimed}}/{{total}} riservati',
        today: 'oggi',
        tomorrow: 'domani',
        inDays_one: 'tra {{count}} giorno',
        inDays_other: 'tra {{count}} giorni',
        daysAgo_one: '{{count}} giorno fa',
        daysAgo_other: '{{count}} giorni fa',
        noDate: 'Senza data',
      },

      actions: { share: 'Condividi', edit: 'Modifica', delete: 'Elimina', leave: 'Abbandona' },

      alerts: {
        deleteTitle: 'Eliminare l\'event?',
        deleteBody: 'Questo rimuoverà tutte le liste, gli articoli e le prenotazioni per tutti.',
        leaveTitle: 'Abbandonare l\'event?',
        leaveBody: 'Verrai rimosso dall\'event e le tue prenotazioni saranno cancellate.',
        cancel: 'Annulla',
        confirmDelete: 'Elimina',
        confirmLeave: 'Abbandona',
      },

      errors: {
        loadFailed: 'Impossibile caricare gli eventi',
        generic: 'Qualcosa è andato storto',
      },
    },

    eventDetail: {
      header: {
        adminNote: 'Sei admin di questo event.',
        memberNote: 'Accesso membro',
      },
      stats: {
        members: 'Membri',
        items: 'Articoli',
        claimed: 'Riservati',
      },
      toolbar: {
        edit: 'Modifica',
        delete: 'Elimina',
      },
      actions: {
        share: 'Condividi',
        leave: 'Abbandona',
        createList: 'Crea lista',
      },
      members: {
        title: 'Membri',
        show: 'Mostra',
        hide: 'Nascondi',
        remove: 'Rimuovi',
        roles: {
          giver: 'donatore',
          recipient: 'destinatario',
          admin: 'admin',
        },
      },
      lists: {
        title: 'Liste',
        emptyTitle: 'Nessuna lista.',
        emptyBody: 'Creane una per iniziare.',
      },
      invite: {
        title: 'Opzioni di invito',
        emailLabel: 'Invia email',
        emailPlaceholder: 'nome@esempio.com',
        cancel: 'Annulla',
        sendEmail: 'Invia email',
        sending: 'Invio…',
        sendCode: 'Invia codice',
        sentTitle: 'Invito inviato',
        sentBody: 'Abbiamo inviato il tuo invito via email.',
        missingEmailTitle: 'Email mancante',
        missingEmailBody: 'Inserisci un indirizzo email.',
        sendFailedTitle: 'Invio non riuscito',
      },
      share: {
        joinWithCode: 'Unisciti al mio event "{{title}}": codice {{code}}',
      },
      alerts: {
        notAllowedTitle: 'Non consentito',
        onlyAdminDelete: 'Solo un admin può eliminare questo event.',
        deleteTitle: 'Eliminare l\'event?',
        deleteBody: 'Questo rimuoverà tutte le liste, gli articoli e le prenotazioni per tutti.',
        cancel: 'Annulla',
        confirmDelete: 'Elimina',

        loadErrorTitle: 'Errore di caricamento',

        removeMemberTitle: 'Rimuovere membro?',
        removeMemberBody: 'Verrà rimosso dall\'event e le sue prenotazioni saranno cancellate.',
        removeFailed: 'Rimozione non riuscita',
        alreadyRemoved: 'Già rimosso',
        memberRemoved: 'Membro rimosso',

        leaveTitle: 'Abbandonare l\'event?',
        leaveBody: 'Verrai rimosso dall\'event e le tue prenotazioni saranno cancellate.',
        notMember: 'Non sei un membro',
        leaveFailed: 'Uscita non riuscita',
        leftEvent: 'Hai lasciato l\'event',
      },
    },

    editEvent: {
      title: 'Modifica event',
      labels: {
        title: 'Titolo',
        date: 'Data',
        joinCode: 'Codice di invito',
      },
      placeholders: {
        title: 'es. Compleanno di Bob',
        date: 'AAAA-MM-GG',
        selectDate: 'Seleziona una data',
      },
      actions: {
        retry: 'Riprova',
        back: 'Indietro',
        copy: 'Copia',
        save: 'Salva modifiche',
      },
      states: {
        viewOnly: 'Sola lettura (non admin)',
        saving: 'Salvataggio…',
      },
      messages: {
        signInRequired: 'Accesso richiesto.',
        notAllowed: 'Non consentito',
        onlyAdmins: 'Solo gli admin possono modificare.',
        titleRequired: 'Titolo richiesto',
        enterTitle: 'Inserisci un titolo.',
        eventUnavailable: 'Event non disponibile.',
        copied: 'Codice copiato',
        copyFailed: 'Copia non riuscita',
        updated: 'Event aggiornato',
        saveFailed: 'Salvataggio non riuscito',
        failedToLoad: 'Impossibile caricare l\'event.',
        notFound: 'Event non trovato o senza accesso.',
      },
    },

    createList: {
      title: 'Crea una lista',
      labels: {
        listName: 'Nome della lista',
      },
      placeholders: {
        listName: 'es. Regali per Bob',
      },
      sections: {
        recipients: {
          title: 'Destinatari (per chi è la lista)',
          help: 'Tocca per selezionare uno o più destinatari.',
        },
        visibility: {
          title: 'Visibilità',
          help: 'Scegli chi può vedere questa lista.',
        },
        exclusions: {
          title: 'Chi escludere',
          help: 'Chi scegli qui non vedrà la lista (anche se è destinatario).',
        },
      },
      visibility: {
        public: 'Visibile a tutti',
        exclude: 'Escludi persone specifiche',
      },
      actions: {
        create: 'Crea lista',
      },
      states: {
        creating: 'Creazione…',
      },
      toasts: {
        loadError: 'Errore di caricamento',
        notSignedIn: 'Non hai effettuato l\'accesso',
        listNameRequired: 'Nome della lista richiesto',
        recipientsRequired: {
          title: 'Destinatari richiesti',
          body: 'Seleziona almeno un destinatario.',
        },
        createFailed: {
          title: 'Creazione non riuscita',
          noId: 'Nessun id lista restituito.',
        },
        notMember: 'Non sei membro di questo event.',
        created: {
          title: 'Lista creata',
          body: 'La tua lista è stata creata correttamente.',
        },
      },
      user: 'Utente {{id}}',
    },

    addItem: {
      title: 'Aggiungi articolo',
      labels: {
        name: 'Nome articolo',
        urlOpt: 'URL (opzionale)',
        priceOpt: 'Prezzo (opzionale)',
        notesOpt: 'Note (opzionale)',
      },
      placeholders: {
        name: 'es. Cuffie con cancellazione del rumore',
        url: 'es. https://esempio.com/prodotto',
        price: 'es. 149,99',
        notes: 'es. Preferisce il tipo over-ear',
      },
      actions: {
        add: 'Aggiungi',
      },
      states: {
        adding: 'Aggiunta…',
      },
      toasts: {
        itemNameRequired: { title: 'Nome richiesto', body: 'Inserisci un nome.' },
        invalidPrice:     { title: 'Prezzo non valido', body: 'Inserisci un numero come 19,99' },
        notSignedIn: 'Non hai effettuato l\'accesso',
        added: 'Articolo aggiunto',
        addFailed: { title: 'Aggiunta non riuscita' },
      },
      errors: {
        generic: 'Errore',
      },
    },

    listDetail: {
      title: 'Lista',
      actions: {
        addItem: 'Aggiungi articolo',
        delete: 'Elimina',
      },
      empty: 'Nessun articolo ancora.',
      summary: {
        label: 'Riservati: {{claimed}} · Non riservati: {{unclaimed}}',
      },
      item: {
        notClaimed: 'Non ancora riservato',
        claimedByYou: 'Riservato da: Tu',
        claimedByName: 'Riservato da: {{name}}',
        hiddenForRecipients: 'Chi acquista resta nascosto ai destinatari.',
        someone: 'Qualcuno',
      },
      confirm: {
        deleteItemTitle: 'Eliminare l\'articolo?',
        deleteItemBody: 'Questo rimuoverà «{{name}}» e le sue prenotazioni.',
        deleteListTitle: 'Eliminare questa lista?',
        deleteListBody: 'Questo rimuoverà la lista e tutti i suoi articoli e prenotazioni. Operazione irreversibile.',
      },
      errors: {
        generic: 'Errore',
        load: 'Si è verificato un problema durante il caricamento della lista.',
        notFound: 'Questa lista non esiste o non hai accesso.',
        notAllowed: 'Non consentito',
        cannotDeleteBody: 'Non puoi eliminare questo articolo.',
        hasClaimsTitle: 'Impossibile eliminare',
        hasClaimsBody: 'Annulla prima la prenotazione o contatta un admin/proprietario.',
        alreadyGoneTitle: 'Non esiste più',
        alreadyGoneBody: 'Questo articolo non esiste più.',
        deleteFailed: 'Eliminazione non riuscita',
        directDeleteBlocked: 'Eliminazione diretta bloccata',
        goBack: 'Indietro',
      },
    },

    allLists: {
      title: 'Tutte le liste',
      eventLabel: 'Event: {{title}}',
      event: 'Event',
      empty: 'Nessuna lista visibile al momento.',
    },

    myClaims: {
      title: 'I miei articoli riservati',
      line: '{{event}} · {{list}}',
      markPurchased: 'Segna come acquistato',
      markNotPurchased: 'Segna come non acquistato',
      empty: 'Non hai ancora riservato nulla.',
      updateFailed: 'Aggiornamento non riuscito',
      fallbackItem: 'Articolo',
      fallbackList: 'Lista',
      fallbackEvent: 'Event',
    },

    createEvent: {
      titleLabel: 'Titolo',
      titlePlaceholder: 'es. Compleanno di Bob',
      descriptionLabel: 'Descrizione (opzionale)',
      descriptionPlaceholder: 'es. Luogo, tema, note…',
      dateLabel: 'Data dell\'event (opzionale)',
      datePlaceholder: 'Seleziona una data',
      done: 'Fine',
      recursLabel: 'Ricorre',
      recurs: { none: 'Nessuna', weekly: 'Settimanale', monthly: 'Mensile', yearly: 'Annuale' },
      create: 'Crea',
      creating: 'Creazione…',
      toastMissingTitleTitle: 'Titolo mancante',
      toastMissingTitleBody: 'Inserisci un titolo dell\'event.',
      toastCreated: 'Event creato',
      toastCreateFailed: 'Creazione non riuscita',
    },

    joinEvent: {
      heading: 'Unisciti a un event',
      codeLabel: 'Inserisci il codice',
      codePlaceholder: 'es. 7G4K-MQ',
      join: 'Unisciti',
      joining: 'Unione in corso…',
      alertEnterTitle: 'Inserisci un codice',
      alertEnterBody: 'Incolla il codice di invito.',
      alertInvalidTitle: 'Codice non valido',
      alertInvalidBody: 'Quel codice non è stato trovato.',
      alertFailedTitle: 'Impossibile unirsi',
    },
  },
} as const;

export default it;
